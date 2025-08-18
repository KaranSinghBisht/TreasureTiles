'use client'
import {
  useAccount, useConnect, useDisconnect, useReadContract, useWriteContract,
  usePublicClient, useChainId, useSwitchChain
} from 'wagmi'
import { baseSepolia } from 'wagmi/chains'
import { TREASURE_ABI } from '@/lib/abi'
import { isBitSet, tileIndex, fmtEth } from '@/lib/utils'
import { useMemo, useState } from 'react'
import { Bomb, Coins, Gem, Hammer, RefreshCw, Wallet } from 'lucide-react'

const CONTRACT = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS as `0x${string}`
const DEFAULT = { rows: 6, cols: 6, bombs: 8, stakeEth: 0.01, callbackGas: 200_000 }

// Types for getRound return
type RoundView = readonly [
  `0x${string}`,      // player
  bigint,            // rows (uint8)
  bigint,            // cols (uint8)
  bigint,            // bombs (uint8)
  boolean,           // active
  boolean,           // settled
  bigint,            // safeReveals (uint64)
  bigint,            // stake (uint256)
  bigint,            // revealedBitmap
  `0x${string}`      // seed (bytes32)
]

// Narrow unknown errors into displayable text
function errText(e: unknown): string {
  if (e && typeof e === 'object') {
    const o = e as { shortMessage?: unknown, message?: unknown }
    if (typeof o.shortMessage === 'string') return o.shortMessage
    if (typeof o.message === 'string') return o.message
  }
  try { return JSON.stringify(e) } catch { return String(e) }
}

export default function Page() {
  const { address, isConnected } = useAccount()
  const { connect, connectors, isPending: isConnecting } = useConnect()
  const { disconnect } = useDisconnect()
  const { writeContractAsync } = useWriteContract()
  const publicClient = usePublicClient()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const [roundId, setRoundId] = useState<number | null>(null)
  const [status, setStatus] = useState<string>('')

  const { data: nextId } = useReadContract({
    abi: TREASURE_ABI, address: CONTRACT, functionName: 'nextId',
    query: { refetchInterval: 5000 }
  }) as { data?: bigint }

  const { data: round } = useReadContract({
    abi: TREASURE_ABI, address: CONTRACT, functionName: 'getRound',
    args: [BigInt(roundId ?? 0)],
    query: { enabled: roundId !== null, refetchInterval: 4000 },
  }) as { data?: RoundView }

  const [_player, rows, cols, bombs, active, settled, safeReveals, stake, revealedBitmap, seed] =
    round ?? ([
      '0x0000000000000000000000000000000000000000', 0n, 0n, 0n, false, false, 0n, 0n, 0n, '0x'
    ] as RoundView)

  const payoutQuery = useReadContract({
    abi: TREASURE_ABI, address: CONTRACT, functionName: 'quotePayout',
    args: [BigInt(roundId ?? 0)],
    query: { enabled: roundId !== null && Boolean(active) && !Boolean(settled), refetchInterval: 4000 }
  }) as { data?: bigint }
  const payout = payoutQuery.data

  async function onCreate() {
    try {
      if (!publicClient) { setStatus('Wallet not ready'); return }
      setStatus('Creating round… (confirm in wallet)')
      const hash = await writeContractAsync({
        chainId: baseSepolia.id,
        abi: TREASURE_ABI, address: CONTRACT, functionName: 'createRound',
        args: [DEFAULT.rows, DEFAULT.cols, DEFAULT.bombs],
        value: BigInt(DEFAULT.stakeEth * 1e18),
      })
      setStatus('Waiting for confirmation…')
      await publicClient.waitForTransactionReceipt({ hash })
      const nid = await publicClient.readContract({ address: CONTRACT, abi: TREASURE_ABI, functionName: 'nextId' }) as bigint
      setRoundId(Number(nid - 1n))
      setStatus('Round created.')
    } catch (e: unknown) {
      setStatus(errText(e))
    }
  }

  async function onRequest() {
    if (roundId === null) return
    try {
      setStatus('Requesting VRF from treasury…')
      await writeContractAsync({
        chainId: baseSepolia.id,
        abi: TREASURE_ABI, address: CONTRACT, functionName: 'requestSeedFromTreasury',
        args: [BigInt(roundId), DEFAULT.callbackGas],
      })
      setStatus('Seed requested. Waiting for fulfillment…')
    } catch (e: unknown) {
      setStatus(errText(e))
    }
  }

  async function onOpen(r: number, c: number) {
    if (roundId === null) return
    try {
      setStatus(`Opening (${r},${c})…`)
      await writeContractAsync({
        chainId: baseSepolia.id,
        abi: TREASURE_ABI, address: CONTRACT, functionName: 'openTile',
        args: [BigInt(roundId), r, c],
      })
      setStatus('Tile opened.')
    } catch (e: unknown) {
      setStatus(errText(e))
    }
  }

  async function onCashout() {
    if (roundId === null) return
    try {
      setStatus('Cashing out…')
      await writeContractAsync({
        chainId: baseSepolia.id,
        abi: TREASURE_ABI, address: CONTRACT, functionName: 'cashOut',
        args: [BigInt(roundId)],
      })
      setStatus('Cashed out.')
    } catch (e: unknown) {
      setStatus(errText(e))
    }
  }

  const grid = useMemo(() => {
    const arr: { r: number, c: number, idx: number, revealed: boolean }[] = []
    const R = Number(rows ?? 0n), C = Number(cols ?? 0n)
    for (let r = 0; r < R; r++) {
      for (let c = 0; c < C; c++) {
        const idx = tileIndex(C, r, c)
        const rev = isBitSet(BigInt(revealedBitmap ?? 0n), idx)
        arr.push({ r, c, idx, revealed: rev })
      }
    }
    return arr
  }, [rows, cols, revealedBitmap])

  return (
    <div className="max-w-5xl mx-auto p-6">
      <header className="flex items-center justify-between gap-4 mb-6">
        <h1 className="text-3xl font-semibold tracking-tight"><span className="text-[#00ffd1]">Treasure</span> Tiles</h1>
        <div className="flex items-center gap-2">
          {isConnected && chainId !== baseSepolia.id && (
            <button className="px-4 py-2 rounded-xl bg-[#12131a] border border-[#222438] text-[#00ffd1]"
                    onClick={() => switchChain({ chainId: baseSepolia.id })}>
              Switch to Base Sepolia
            </button>
          )}
          {!isConnected ? (
            <button
              className="px-4 py-2 rounded-xl bg-[#12131a] border border-[#222438] hover:bg-[#171823] text-[#00ffd1]"
              onClick={() => connect({ connector: connectors.find(c => c.id === 'injected') ?? connectors[0] })}
              disabled={isConnecting}
            >
              <span className="inline-flex items-center gap-2"><Wallet size={16}/> {isConnecting ? 'Connecting…' : 'Connect'}</span>
            </button>
          ) : (
            <button className="px-4 py-2 rounded-xl bg-[#12131a] border border-[#222438]" onClick={() => disconnect()}>
              {address?.slice(0,6)}…{address?.slice(-4)}
            </button>
          )}
        </div>
      </header>

      <div className="grid md:grid-cols-3 gap-5">
        <section className="md:col-span-1 bg-[#12131a]/70 backdrop-blur border border-[#1b1d2b] rounded-2xl p-5">
          <div className="text-xs text-[#9ca3af]">Contract</div>
          <div className="text-xs break-all mb-3">{CONTRACT}</div>

          <div className="flex items-center gap-2 mb-3">
            <input
              className="bg-[#12131a] border border-[#222438] rounded-xl px-3 py-2 w-28 focus:outline-none focus:ring-2 focus:ring-[#00ffd1]"
              type="number" placeholder="Round ID"
              value={roundId ?? ''}
              onChange={e => setRoundId(e.target.value ? Number(e.target.value) : null)}
            />
            <button
              className="px-3 py-2 rounded-xl bg-[#12131a] border border-[#222438]"
              onClick={() => {
                const n = (nextId ?? 0n)
                setRoundId(n > 0n ? Number(n - 1n) : 0)
              }}
            >
              Latest
            </button>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm mb-3">
            <div>Rows: <b>{Number(rows||0n)}</b></div>
            <div>Cols: <b>{Number(cols||0n)}</b></div>
            <div>Bombs: <b>{Number(bombs||0n)}</b></div>
            <div>Safe: <b>{String(safeReveals||0n)}</b></div>
            <div>Stake: <b>{fmtEth(BigInt(stake||0n)).toFixed(4)} ETH</b></div>
            <div>Active: <b className={active ? 'text-[#19ff81]' : 'text-[#9ca3af]'}>{String(active)}</b></div>
            <div>Settled: <b>{String(settled)}</b></div>
          </div>

          {active && !settled && payout !== undefined && (
            <div className="mt-2 text-sm">
              <div className="text-[#9ca3af]">Estimated payout (capped 2×)</div>
              <div className="text-[#00ffd1] text-lg">{fmtEth(payout).toFixed(5)} ETH</div>
            </div>
          )}

          <div className="h-px bg-[#202233] my-3" />

          <div className="flex flex-wrap gap-2">
            <button className="px-4 py-2 rounded-xl bg-[#12131a] border border-[#222438] text-[#00ffd1] hover:shadow-[0_0_30px_rgba(0,255,209,0.3)]"
              onClick={onCreate}>
              <span className="inline-flex items-center gap-2"><Hammer size={16}/> Create (0.01)</span>
            </button>
            <button className="px-4 py-2 rounded-xl bg-[#12131a] border border-[#222438]"
              onClick={onRequest} disabled={roundId===null || active || settled}>
              <span className="inline-flex items-center gap-2"><RefreshCw size={16}/> Request Seed</span>
            </button>
            <button className="px-4 py-2 rounded-xl bg-[#12131a] border border-[#222438]"
              onClick={onCashout} disabled={!active || settled}>
              <span className="inline-flex items-center gap-2"><Coins size={16}/> Cash Out</span>
            </button>
          </div>

          <div className="text-xs text-[#9ca3af] mt-3">{status}</div>
          {seed && seed !== '0x' && active && <div className="text-xs break-all">Seed: {seed}</div>}
        </section>

        <section className="md:col-span-2 bg-[#12131a]/70 backdrop-blur border border-[#1b1d2b] rounded-2xl p-5">
          <h2 className="font-medium mb-3 text-[#9ca3af]">Board</h2>
          <div className="grid grid-cols-6 gap-2">
            {Array.isArray(grid) && grid.map(t => (
              <button
                key={t.idx}
                className={`w-12 h-12 md:w-14 md:h-14 rounded-xl border border-[#24263a] flex items-center justify-center select-none
                  ${t.revealed ? 'bg-[#0e1320] text-[#19ff81] border-[#19ff81]/30' : 'bg-[#0b0f1a] hover:bg-[#0d1221]'}`}
                onClick={() => onOpen(t.r, t.c)}
                disabled={!active || settled || t.revealed}
                title={`${t.r},${t.c}`}
              >
                {t.revealed ? <Gem size={16}/> : <Bomb size={16} className="opacity-20" />}
              </button>
            ))}
          </div>
        </section>
      </div>

      <footer className="text-center text-xs text-[#9ca3af] mt-8">
        Testnet only (Base Sepolia 84532). Max stake 0.01, max payout 2×, VRF fees paid by treasury.
      </footer>
    </div>
  )
}
