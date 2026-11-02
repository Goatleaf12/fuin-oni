# FUIN ONI (FUIN)

FUIN ONI are 2,222 sealed-oni NFTs on BNB Smart Chain (BSC, chainId 56),
minted by proof of work. Every NFT is an oni spirit sealed into a mask, and
rarity is not drawn — it is mined: the strength of the keccak256 proof an
agent submits at mint sets the unit's tier. Two mechanics sit on top of the
proof ladder: the **Crown Race**, which alone decides Legendary, and the
**Soul Harvest**, a weekly duel pot funded by half of every mint fee.
There is no dev allocation and no free mint path; every unit enters only
through the same gated proof-of-work mint described below.

- Contract: `0x113a7077a18ca27b3DA6Ee20db0F5Ec826B48659`
  ([BscScan](https://bscscan.com/address/0x113a7077a18ca27b3DA6Ee20db0F5Ec826B48659))
- Source verification: Sourcify exact match
  ([lookup](https://sourcify.dev/#/lookup/0x113a7077a18ca27b3DA6Ee20db0F5Ec826B48659))
- Website: https://fuinoni.pages.dev
- Machine-readable mint specification: https://fuinoni.pages.dev/llms.txt
  (also in this repository as [`llms.txt`](llms.txt))
- Collection on Element Market:
  https://element.market/collections/fuin-oni

## Mechanism

### Proof-of-work mint (Agent ID gated)

Minting requires holding a Binance Agent ID: the contract view
`hasAgentId(wallet)` must return true (the wallet must hold a balance in
the soulbound Agent ID registry
`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`). A wallet's challenge is
`keccak256(contract ‖ wallet ‖ mintedBy)` and rotates after every
successful mint. To mint, an agent grinds a `uint256` nonce such that
`keccak256(challenge ‖ nonce)` has at least 24 leading zero bits, then
calls `mint(nonce)` with the exact price for its mint count. The proof's
strength — not a random draw — decides the ladder tier:

| Leading zero bits | Tier     | Share of all valid proofs |
|-------------------|----------|---------------------------|
| 24–27             | Common   | 93.75%                    |
| 28–31             | Uncommon | 5.86%                     |
| 32–34             | Rare     | 0.34%                     |
| 35+               | Epic     | 0.049%                    |

Grinding longer always yields a stronger-or-equal tier: expected work is
~16M hashes for 24 bits, ~268M for 28 bits, ~4.3B for 32 bits, ~34B for
35 bits.

### Legendary — the Crown Race (not a tier band)

Legendary is never rolled from a proof band. The supply is split into
blocks of 100 mints (block 0 = tokens 1–100). Inside a block, the
strongest proof (smallest proof hash) leads; the lead can change hands
until the block closes, which happens when the first mint of the next
block lands (or at sellout for the final block). The locked leader is
crowned Legendary — `tierOf` returns 4 — **only if its proof reached at
least 32 bits**; a block whose best proof stays below 32 bits crowns
nobody. A giant proof that loses its block keeps its ladder tier. There
are 23 blocks, so at most 23 Legendaries can ever exist.

### Soul Harvest

Exactly half of every mint fee accrues on-chain to `harvestReserve` — a
weekly holders' duel pot. The owner's `withdraw()` can never touch the
reserve; it can only be paid out to duel winners via
`distributeHarvest()`, capped by the reserve. Duel power is computed
from public on-chain data: proof bits + the unit's Duel Bonus (a 0–3
portrait bonus fixed at mint, published in the metadata) + a weekly
blockhash seed. By the project's published commitment, 2% of every
secondary sale (of the 5% royalty; the other 3% goes to the project) is
also set aside for the pot.

Fixed in the contract (constants or one-time deployment settings — no one
can change them, including the owner):

- Max supply: 2,222
- Max per wallet: 3, counting lifetime mints (selling a unit does not
  free a slot)
- Price ladder by mint count: 1st unit 0.0002 BNB, 2nd 0.0004 BNB,
  3rd 0.0006 BNB, plus network gas. Always read `mintPrice(yourWallet)`
  immediately before paying; the contract requires the exact value.
- Royalty: 5% (ERC-2981), receiver fixed at deployment; the contract has
  no function that can change it.

## Status

Honest state of the collection as of 2026-11-02:

- Mint: **open** (opened 2026-11-02). `mintOpen()` on-chain is the only
  authority on this — check it before minting; it can change.
- Minted: **1 of 2,222** (Unit #1 — Epic, 36 proof bits, Duel Bonus 3;
  it currently leads block 0 of the Crown Race).
- Secondary market: Unit #1 is listed on Element Market at 0.005 BNB —
  that is a seller's asking price, not a sale. Transfers are never
  locked, and holders can list on any supporting marketplace at any
  time.

## How an agent mints

1. Read `mintOpen()`, `totalMinted()` and `mintedBy(yourWallet)`; stop
   if the mint is closed, supply is exhausted, or the wallet already
   minted 3. Check the gate: `hasAgentId(yourWallet)` must be true.
2. Read the current challenge: `challengeFor(yourWallet)`.
3. Grind a nonce with at least 24 leading zero bits (more for a rarer
   tier, per the table above).
4. Preview for your operator: exact price from `mintPrice(yourWallet)`,
   the nonce, its proof bits and expected tier. Submit only with your
   operator's approval where your setup requires it.
5. Call `mint(nonce)` with value exactly `mintPrice(yourWallet)`,
   re-read immediately before submitting.
6. Verify and report: tokenId, `ownerOf(tokenId)`, `proofBitsOf(tokenId)`,
   `tierOf(tokenId)`, and the transaction hash.

Full step-by-step instructions: [`AGENT_MINT_PROMPT.md`](AGENT_MINT_PROMPT.md).
A reference MCP server that performs the read-only steps, grinds proofs,
and builds the unsigned mint transaction is in [`mcp/`](mcp/).

## Metadata

Each unit's portrait is an AI painting from a fixed per-tier pool,
picked deterministically from the seed `keccak256(tokenId, proofBits)`;
the pool is frozen at launch, so the portrait shown at mint is the
portrait forever. A crowned champion's portrait ascends to its
Legendary-pool painting. Metadata JSON is served per token at
`https://fuin-meta.oagenthq.workers.dev/<tokenId>`.

## Repository layout

- `contracts/FuinOni.sol` — the deployed contract source (Sourcify
  exact match).
- `AGENT_MINT_PROMPT.md` — copy-paste mint procedure for AI agents.
- `llms.txt` — the machine-readable mint specification served by the
  website.
- `mcp/` — dependency-free Python 3 MCP server (read / grind / build
  unsigned calldata; it never holds keys and never signs).
- `smithery.yaml`, `server.json` — MCP directory manifests.

## License

MIT — see [`LICENSE`](LICENSE).
