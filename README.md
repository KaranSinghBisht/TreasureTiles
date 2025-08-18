# Treasure Tiles — VRF-seeded Mines game (Base Sepolia)

Provably-fair "mines/tiles" game powered by dcipher VRF, written in Solidity (Foundry) with a Next.js + wagmi/viem frontend.
Runs on Base Sepolia (chain id 84532). Testnet only.

**Current contract:** `0xa3c094f56cC97Fb1C39b3788C6392692CeEaA979` (Base Sepolia)

## ✨ Features

- **Provable randomness**: seed delivered by dcipher VRF; bombs selected via partial Fisher–Yates (unbiased).
- **Risk curve**: Estimated cash-out starts at 0.2× of stake after seed, grows linearly with each safe reveal, caps at 2×.
- **Auto-cash at cap**: If you reach 2× during a reveal, the contract settles and pays immediately.
- **Safety rails (testnet)**:
  - Max stake 0.01 ETH
  - Max payout 2×
  - Solvency check on create (treasury must cover 2× of the stake)
- **Treasury management**:
  - Anyone can fund treasury for VRF fees/payout headroom
  - Owner can withdraw leftover funds (test ETH recycling)
- **Neon dark UI** with wallet network guard & chain switching.

## 🚀 Quick start

### Prereqs

- Node ≥ 20 (recommended)
- Foundry (forge, cast)
- A wallet with a little Base Sepolia ETH
- RPC URL for Base Sepolia (e.g. https://sepolia.base.org)

### 1) Contracts (Foundry)

```bash
git clone <your-repo>
cd treasure-tiles-foundry

# .env
echo "PRIVATE_KEY=<your-private-key>" >> .env
echo "BASE_SEPOLIA_RPC_URL=<your-base-sepolia-rpc>" >> .env

forge install
forge build

# Deploy
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvvv

# Copy the printed address and export it:
export TREASURE_ADDR=<deployed-address>
```

**Fund treasury** (for payouts + VRF fees):

```bash
cast send $TREASURE_ADDR --value 30000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

**Create a round + request VRF** (CLI demo):

```bash
# Create round (6x6, 8 bombs) with 0.01 ETH stake
cast send $TREASURE_ADDR "createRound(uint8,uint8,uint8)" 6 6 8 \
  --value 10000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Find latest id
RID_HEX=$(cast call $TREASURE_ADDR "nextId()(uint256)" --rpc-url $BASE_SEPOLIA_RPC_URL)
RID_DEC=$(cast --to-dec $RID_HEX); export ROUND_ID=$((RID_DEC-1)); echo "ROUND_ID=$ROUND_ID"

# Ask VRF from treasury (no msg.value; contract pays exact fee)
cast send $TREASURE_ADDR "requestSeedFromTreasury(uint256,uint32)" $ROUND_ID 200000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

### 2) Frontend (Next.js)

```bash
cd ../tiles-frontend

# env
printf "NEXT_PUBLIC_CONTRACT_ADDRESS=%s\nNEXT_PUBLIC_RPC_URL=%s\n" \
  "<deployed-address>" "https://sepolia.base.org" > .env.local

npm i
npm run dev
```

Open http://localhost:3000
Connect wallet → Switch to Base Sepolia if prompted → Create → Request Seed → play.

## 🧩 How it works

### Game flow

1. `createRound(rows, cols, bombs)` (payable; ≤ 0.01 ETH). Contract checks it can afford 2× payout.
2. `requestSeedFromTreasury(id, gasLimit)`. Contract queries dcipher's `calculateRequestPriceNative`, pays the exact fee from its balance, and requests VRF.
3. `onRandomnessReceived` stores the seed, computes bombs via partial Fisher–Yates (unique, unbiased), and activates the round.
4. Player calls `openTile`.
   - If bomb → round settles loss to 0.
   - If safe → `safeReveals++`; `quotePayout` rises linearly (0.2× → 2×). If it reaches 2×, the contract auto-cashes and pays.
5. Player can `cashOut` any time before hitting a bomb; payout = stake × multiplier (house fee = 0 bps in test build).

### Payout formula (linear ramp)

- **Start multiplier**: 0.2×
- **Cap multiplier**: 2.0×
- Increases linearly with each safe reveal up to the cap.

### Provable fairness

- The seed from dcipher VRF is emitted in `SeedFulfilled`.
- Bomb positions are derived by shuffling the first `bombs` indices using partial Fisher–Yates with `keccak256(seed, salt)` as the RNG.
- Anyone can reconstruct bomb indices off-chain from the seed + board params.

## 🧱 Contract surface

### Game

- `createRound(uint8 rows, uint8 cols, uint8 bombs)` payable returns (uint256 id)
- `requestSeedFromTreasury(uint256 id, uint32 callbackGasLimit)`
- `openTile(uint256 id, uint8 row, uint8 col)`
- `cashOut(uint256 id)`
- `getRound(uint256 id)` → (player, rows, cols, bombs, active, settled, safeReveals, stake, revealedBitmap, seed)
- `quotePayout(uint256 id)` → uint256
- `quoteVrfFee(uint32 callbackGasLimit)` → uint256

### Treasury

- `fund()` payable
- `withdraw(address to, uint256 amount)` (owner)

### Events

`RoundCreated`, `SeedRequested`, `SeedFulfilled`, `TileRevealed`, `BombHit`, `CashedOut`, `Treasure_Funded`, `Treasure_Withdrawn`

## 🖥️ Frontend details

**Stack**: Next.js (App Router) + Tailwind, wagmi + viem

### ENV

- `NEXT_PUBLIC_CONTRACT_ADDRESS` — target contract
- `NEXT_PUBLIC_RPC_URL` — Base Sepolia RPC (e.g. https://sepolia.base.org)

### UX guards

- Forces chainId: 84532 on writes (prompts wallet to switch)
- "Latest" round helper
- Status messages surfaced from viem/wagmi errors

## ☁️ Deploying to Vercel

**Monorepo note**: set Root Directory to `tiles-frontend/`.

### Environment Variables (Preview + Production)

- `NEXT_PUBLIC_CONTRACT_ADDRESS` = your deployed address
- `NEXT_PUBLIC_RPC_URL` = https://sepolia.base.org

### Build & Runtime

- **Framework**: Next.js
- **Node.js**: 20
- **Install**: `npm i`
- **Build**: `npm run build`

Deploy. Connect wallet, switch to Base Sepolia, and play.

## 🔧 Maintenance & owner ops

### Funding treasury

```bash
cast send $TREASURE_ADDR --value 20000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### Withdraw test ETH

```bash
cast send $TREASURE_ADDR "withdraw(address,uint256)" <your-wallet> <amountWei> \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

## 🧪 Troubleshooting

- **Wallet says "wrong chain (31337 vs 84532)"**
  - Switch wallet to Base Sepolia or use the UI's "Switch to Base Sepolia" button.

- **"bad fee" when requesting seed**
  - Use `requestSeedFromTreasury` (contract pays the exact current price), or if using a direct function, re-quote right before sending.

- **UI stuck after Create**
  - Use "Latest" to load the newly created round (or type the id).

- **Payout showed > 2×**
  - Fixed: quote is clamped and contract auto-cashes at 2×.

## ⚠️ Disclaimer

This is a testnet demo for educational purposes only. Not audited. Do not deploy to mainnet as-is. Understand local laws around games of chance.

## 📄 License

MIT

## 🙌 Acknowledgements

- dcipher VRF & randomness-solidity
- wagmi, viem
- Base (L2)
- Next.js & Tailwind

## Roadmap (nice-to-have)

- Live event toasts (TileRevealed/CashedOut)
- Off-chain "Verify bombs from seed" tool
- Multi-round history & leaderboards
- Adjustable start multiplier (e.g., 0.15×/0.25×) and curves (ease-in/out)

Have feedback or found an edge case? Open an issue or ping me!