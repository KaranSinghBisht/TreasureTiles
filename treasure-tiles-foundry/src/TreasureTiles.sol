// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RandomnessReceiverBase} from "randomness-solidity/src/RandomnessReceiverBase.sol";

interface IRandomnessSender {
    function calculateRequestPriceNative(
        uint32 callbackGasLimit
    ) external view returns (uint256);
    function requestRandomness(
        uint32 callbackGasLimit
    ) external payable returns (uint256);
}

/// @title TreasureTiles — VRF-seeded Mines-style game (dcipher)
/// @notice Safe-for-demo version:
///  - MAX_STAKE = 0.01 ether
///  - MAX payout cap = 2.00x
///  - Solvency check on createRound (contract balance must cover 2x of stake)
///  - Losses stay in contract treasury; owner can withdraw
///  - Exact VRF fee quoting supported
contract TreasureTiles is RandomnessReceiverBase, ReentrancyGuard {
    struct Round {
        address player;
        uint8 rows;
        uint8 cols;
        uint8 bombs;
        bool active; // seed placed & bombs computed
        bool settled;
        uint256 requestId; // request id from dcipher (uint64 in some lib versions)
        uint64 safeReveals;
        uint256 stake; // wei stake
        uint256 bombBitmap; // bit i => 1 if bomb
        uint256 revealedBitmap; // bit i => 1 if revealed
        bytes32 seed; // stored for verification
    }

    // --- Storage ---
    uint256 public nextId;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => uint256) private reqToRound; // requestId => roundId

    // --- Config ---
    address public immutable randomnessSenderProxy;
    uint8 public constant MAX_ROWS = 10;
    uint8 public constant MAX_COLS = 10;

    // stake/payout limits for safety on testnet
    uint256 public constant MAX_STAKE = 0.01 ether; // user stake cap
    uint16 public constant MAX_MULT_X100 = 200; // 2.00x max payout

    uint256 public constant ONE = 1e18;
    uint16 public constant HOUSE_FEE_BPS = 0; // 0–10000 (10000 = 100%)

    // Add near your other constants
    uint256 public constant BASE_MULT_WAD = 0.2e18; // 0.2x start
    uint256 public constant CAP_MULT_WAD = 2e18; // 2.0x cap

    // --- Events ---
    event RoundCreated(
        uint256 indexed id,
        address indexed player,
        uint8 rows,
        uint8 cols,
        uint8 bombs,
        uint256 stake
    );
    event SeedRequested(
        uint256 indexed id,
        uint256 requestId,
        uint32 callbackGasLimit,
        uint256 feeQuoted
    );
    event SeedFulfilled(uint256 indexed id, uint256 requestId, bytes32 seed);
    event TileRevealed(
        uint256 indexed id,
        uint256 idx,
        bool bomb,
        uint64 safeReveals
    );
    event CashedOut(uint256 indexed id, address indexed player, uint256 amount);
    event BombHit(uint256 indexed id);
    event Treasure_Funded(address indexed from, uint256 amount);
    event Treasure_Withdrawn(address indexed to, uint256 amount);

    /// Base needs (senderProxy, owner). Owner = deployer; we use onlyOwner from the base.
    constructor(
        address _randomnessSenderProxy
    ) RandomnessReceiverBase(_randomnessSenderProxy, msg.sender) {
        randomnessSenderProxy = _randomnessSenderProxy;
    }

    // ========= Game API =========

    /// @dev User stakes <= MAX_STAKE. Contract must be solvent for max payout (2x).
    function createRound(
        uint8 rows,
        uint8 cols,
        uint8 bombs
    ) external payable nonReentrant returns (uint256 id) {
        require(
            rows > 0 && cols > 0 && rows <= MAX_ROWS && cols <= MAX_COLS,
            "bad dims"
        );
        uint256 n = uint256(rows) * uint256(cols);
        require(bombs > 0 && bombs < n, "bad bombs");
        require(msg.value > 0 && msg.value <= MAX_STAKE, "bad stake");

        // Solvency check: after receiving stake, contract must cover max payout (2x)
        uint256 maxPayout = (msg.value * MAX_MULT_X100) / 100; // e.g. 2.00x
        require(address(this).balance >= maxPayout, "insufficient liquidity");

        id = nextId++;
        rounds[id] = Round({
            player: msg.sender,
            rows: rows,
            cols: cols,
            bombs: bombs,
            active: false,
            settled: false,
            requestId: 0,
            safeReveals: 0,
            stake: msg.value,
            bombBitmap: 0,
            revealedBitmap: 0,
            seed: 0x0
        });
        emit RoundCreated(id, msg.sender, rows, cols, bombs, msg.value);
    }

    /// @notice Exact-fee path: quote VRF price and require exact value.
    function requestSeedDirectExact(
        uint256 id,
        uint32 callbackGasLimit
    ) external payable nonReentrant {
        Round storage r = _ownedActiveOrPending(id);
        require(!r.active && r.requestId == 0, "already requested");
        uint256 price = IRandomnessSender(randomnessSenderProxy)
            .calculateRequestPriceNative(callbackGasLimit);
        require(msg.value == price, "bad fee");
        (uint256 reqId /*priceAgain*/, ) = _requestRandomnessPayInNative(
            callbackGasLimit
        );
        r.requestId = reqId;
        reqToRound[reqId] = id;
        emit SeedRequested(id, reqId, callbackGasLimit, price);
    }

    /// @notice Buffer-fee path: send >= quoted price (for convenience).
    function requestSeedDirect(
        uint256 id,
        uint32 callbackGasLimit
    ) external payable nonReentrant {
        Round storage r = _ownedActiveOrPending(id);
        require(!r.active && r.requestId == 0, "already requested");
        uint256 price = IRandomnessSender(randomnessSenderProxy)
            .calculateRequestPriceNative(callbackGasLimit);
        require(msg.value >= price, "fee too low");
        (uint256 reqId /*priceAgain*/, ) = _requestRandomnessPayInNative(
            callbackGasLimit
        );
        r.requestId = reqId;
        reqToRound[reqId] = id;
        emit SeedRequested(id, reqId, callbackGasLimit, price);
    }

    function openTile(uint256 id, uint8 row, uint8 col) external nonReentrant {
        Round storage r = rounds[id];
        require(msg.sender == r.player, "not your round");
        require(r.active && !r.settled, "not ready/settled");
        uint256 idx = _index(r, row, col);
        require(!_isSet(r.revealedBitmap, idx), "already");

        r.revealedBitmap = _setBit(r.revealedBitmap, idx);

        bool bomb = _isSet(r.bombBitmap, idx);
        if (bomb) {
            r.active = false;
            r.settled = true;
            r.stake = 0; // loss retained in treasury
            emit TileRevealed(id, idx, true, r.safeReveals);
            emit BombHit(id);
            return;
        }

        r.safeReveals += 1;
        emit TileRevealed(id, idx, false, r.safeReveals);

        // after you increment r.safeReveals and emitting TileRevealed
        uint256 payoutNow = quotePayout(id);
        uint256 capPayout = (r.stake * CAP_MULT_WAD) / 1e18;
        if (payoutNow >= capPayout) {
            r.active = false;
            r.settled = true;
            (bool ok, ) = r.player.call{value: payoutNow}("");
            require(ok, "payout failed");
            emit CashedOut(id, r.player, payoutNow);
            return;
        }

        uint256 maxSafe = uint256(r.rows) * uint256(r.cols) - r.bombs;
        if (r.safeReveals == maxSafe) {
            _cashOut(id);
        }
    }

    function cashOut(uint256 id) external nonReentrant {
        _cashOut(id);
    }

    // ========= Views & Helpers =========

    function quoteVrfFee(
        uint32 callbackGasLimit
    ) external view returns (uint256) {
        return
            IRandomnessSender(randomnessSenderProxy)
                .calculateRequestPriceNative(callbackGasLimit);
    }

    /// EV-fair multiplier (1e18 scaled), then capped at MAX_MULT_X100.
    function _fairMultCapped(
        uint8 rows,
        uint8 cols,
        uint8 bombs,
        uint64 safeReveals
    ) internal pure returns (uint256) {
        uint256 n = uint256(rows) * uint256(cols);
        require(bombs > 0 && bombs < n, "bad bombs");
        require(safeReveals <= n - bombs, "t too big");

        uint256 p1e18 = ONE;
        for (uint256 i = 0; i < safeReveals; i++) {
            p1e18 = (p1e18 * (n - bombs - i)) / (n - i);
        }
        if (p1e18 == 0) return uint256(MAX_MULT_X100) * 1e16; // cap
        uint256 mult = (ONE * ONE) / p1e18;
        uint256 cap = uint256(MAX_MULT_X100) * 1e16; // e.g. 200 * 1e16 = 2e18
        if (mult > cap) mult = cap;
        return mult;
    }

    // Replace your quotePayout with this version
    function quotePayout(uint256 id) public view returns (uint256) {
        Round storage r = rounds[id];
        if (!r.active || r.settled) return 0;

        uint256 maxSafe = uint256(r.rows) * uint256(r.cols) - uint256(r.bombs);
        if (maxSafe == 0) return 0;

        // linear ramp from 0.2x to 2.0x with safe reveals
        uint256 mulWad = BASE_MULT_WAD +
            ((CAP_MULT_WAD - BASE_MULT_WAD) * uint256(r.safeReveals)) /
            maxSafe;

        if (mulWad > CAP_MULT_WAD) mulWad = CAP_MULT_WAD;
        return (r.stake * mulWad) / 1e18;
    }

    function getRound(
        uint256 id
    )
        external
        view
        returns (
            address player,
            uint8 rows,
            uint8 cols,
            uint8 bombs,
            bool active,
            bool settled,
            uint64 safeReveals,
            uint256 stake,
            uint256 revealedBitmap,
            bytes32 seed
        )
    {
        Round storage r = rounds[id];
        return (
            r.player,
            r.rows,
            r.cols,
            r.bombs,
            r.active,
            r.settled,
            r.safeReveals,
            r.stake,
            r.revealedBitmap,
            r.seed
        );
    }

    function isRevealed(
        uint256 id,
        uint8 row,
        uint8 col
    ) external view returns (bool) {
        Round storage r = rounds[id];
        uint256 idx = _index(r, row, col);
        return _isSet(r.revealedBitmap, idx);
    }
    /// @notice Request VRF using the contract's own balance (no msg.value).
    ///         Solves fee drift: price is quoted and paid within the same call.
    ///         Allowed by the round player or the owner.
    function requestSeedFromTreasury(
        uint256 id,
        uint32 callbackGasLimit
    ) external nonReentrant {
        Round storage r = rounds[id];
        require(msg.sender == r.player || msg.sender == owner(), "not allowed");
        require(
            !r.active && !r.settled && r.requestId == 0,
            "already requested/settled"
        );

        uint256 price = IRandomnessSender(randomnessSenderProxy)
            .calculateRequestPriceNative(callbackGasLimit);
        require(address(this).balance >= price, "treasury < fee");

        // Pay the proxy exactly the current price from contract balance.
        uint256 reqId = IRandomnessSender(randomnessSenderProxy)
            .requestRandomness{value: price}(callbackGasLimit);

        r.requestId = reqId;
        reqToRound[reqId] = id;
        emit SeedRequested(id, reqId, callbackGasLimit, price);
    }

    // ========= VRF callback =========
    /// NOTE: If your installed library expects `uint64`, change the type here and in mappings.
    function onRandomnessReceived(
        uint256 requestID,
        bytes32 seed
    ) internal override {
        uint256 id = reqToRound[requestID];
        require(
            id != 0 || (nextId > 0 && rounds[0].requestId == requestID),
            "unknown req"
        );

        Round storage r = rounds[id];
        require(!r.active && !r.settled, "bad state");

        uint256 n = uint256(r.rows) * uint256(r.cols);
        r.seed = seed;
        r.bombBitmap = _computeBombBitmap(seed, n, r.bombs);
        r.active = true;

        emit SeedFulfilled(id, requestID, seed);
    }

    // ========= Internal =========

    function _cashOut(uint256 id) internal {
        Round storage r = rounds[id];
        require(msg.sender == r.player, "not your round");
        require(r.active && !r.settled, "not ready/settled");

        uint256 gross = quotePayout(id); // use linear ramp payout
        // optional house fee (currently 0)
        uint256 net = (gross * (10000 - HOUSE_FEE_BPS)) / 10000;

        r.active = false;
        r.settled = true;
        r.stake = 0;

        (bool ok, ) = msg.sender.call{value: net}("");
        require(ok, "transfer fail");
        emit CashedOut(id, msg.sender, net);
    }

    function _ownedActiveOrPending(
        uint256 id
    ) internal view returns (Round storage r) {
        r = rounds[id];
        require(r.player == msg.sender, "not your round");
        require(!r.settled, "settled");
    }

    function _index(
        Round storage r,
        uint8 row,
        uint8 col
    ) internal view returns (uint256) {
        require(row < r.rows && col < r.cols, "oob");
        return uint256(row) * uint256(r.cols) + uint256(col);
    }

    function _isSet(uint256 bitmap, uint256 idx) internal pure returns (bool) {
        return (bitmap & (uint256(1) << idx)) != 0;
    }

    function _setBit(
        uint256 bitmap,
        uint256 idx
    ) internal pure returns (uint256) {
        return bitmap | (uint256(1) << idx);
    }

    /// Picks exactly `bombs` unique indices from 0..n-1 via partial Fisher–Yates (unbiased).
    function _computeBombBitmap(
        bytes32 seed,
        uint256 n,
        uint256 bombs
    ) internal pure returns (uint256 bm) {
        require(n <= 256, "grid too big");
        uint256[] memory arr = new uint256[](n);
        for (uint256 i = 0; i < n; i++) arr[i] = i;

        uint256 ctr = 0;
        for (uint256 i = 0; i < bombs; i++) {
            uint256 j = i + _uniform(seed, ctr++, n - i);
            (arr[i], arr[j]) = (arr[j], arr[i]);
            bm |= (uint256(1) << arr[i]);
        }
    }

    /// Uniform integer in [0, range-1] without modulo bias (rejection).
    function _uniform(
        bytes32 seed,
        uint256 salt,
        uint256 range
    ) internal pure returns (uint256) {
        require(range > 0, "range 0");
        uint256 limit = type(uint256).max - (type(uint256).max % range);
        bytes32 h = keccak256(abi.encodePacked(seed, salt));
        uint256 x = uint256(h);
        while (x >= limit) {
            h = keccak256(abi.encodePacked(h));
            x = uint256(h);
        }
        return x % range;
    }

    // ========= Treasury =========

    /// @notice Anyone can fund the game treasury (owner or external).
    function fund() external payable {
        require(msg.value > 0, "no value");
        emit Treasure_Funded(msg.sender, msg.value);
    }

    /// @notice Owner can withdraw treasury funds (e.g., to recycle test ETH).
    function withdraw(
        address payable to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "bad to");
        require(amount <= address(this).balance, "insufficient");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "withdraw failed");
        emit Treasure_Withdrawn(to, amount);
    }

    receive() external payable {
        emit Treasure_Funded(msg.sender, msg.value);
    }
}
