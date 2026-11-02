# FUIN ONI — MCP server

A dependency-free Python 3 [MCP](https://modelcontextprotocol.io) server
(stdio transport) for the FUIN ONI proof-of-work NFT collection on
BNB Smart Chain. It reads live collection state (including the Crown
Race and the Soul Harvest reserve), looks up minted units, grinds mint
proofs, and builds the unsigned mint transaction.

It **never holds keys and never signs or sends transactions** — the
calling agent signs with its own wallet. See
[`../AGENT_MINT_PROMPT.md`](../AGENT_MINT_PROMPT.md) for the full mint
procedure and safety rules.

## Run

Requires Python 3.8+ and nothing else (standard library only; it ships
its own pure-Python Keccak-256 — Ethereum Keccak, not NIST SHA3).

```bash
python3 mcp/fuin_mcp.py
```

The server speaks newline-delimited JSON-RPC on stdin/stdout, per the
MCP stdio transport.

## Tools

| Tool | Arguments | What it does |
|------|-----------|--------------|
| `collection_info` | — | Live reads: `totalMinted`, `MAX_SUPPLY`, remaining supply, `mintOpen`, Crown Race state of the current block, Soul Harvest reserve, contract BNB balance. |
| `unit_info` | `token_id` | `proofBitsOf` + `tierOf` for a minted unit, plus its block index and metadata URL. |
| `grind_proof` | `wallet`, `minted_by`, `target_bits` | Computes the challenge exactly as the contract does and grinds a nonce with at least `target_bits` leading zero bits; the proof is re-verified before return. |
| `mint_calldata` | `wallet`, `minted_by`, `target_bits` (≥ 24) | Grinds, checks the Agent ID gate live, then returns the **unsigned** `{to, value, data}` for `mint(uint256)` at the exact price-ladder value for that mint count. |

Notes:

- Minting is gated: the wallet must hold a Binance Agent ID
  (`hasAgentId(wallet)` on the contract must return true).
  `mint_calldata` reads the gate live and reports it; a mint from a
  wallet without an Agent ID reverts.
- The challenge binds the wallet's current `mintedBy` count and rotates
  after every mint — always pass the wallet's current on-chain count,
  and re-check `mintOpen()`, `mintedBy`, `hasAgentId` and `mintPrice`
  immediately before submitting anything built from `mint_calldata`.
- Ladder tier by proof bits: 24–27 Common, 28–31 Uncommon, 32–34 Rare,
  35+ Epic. Legendary is not a band — it is the crown of a block of
  100 mints, awarded to the block's strongest proof (≥ 32 bits) when
  the block closes.
- The pure-Python grinder is a reference implementation. At 24 bits
  (~16M hashes expected) it is far too slow for production use;
  production agents with compiled grinders should use those and this
  server for reads and verification of the scheme.

## MCP client configuration

Claude Desktop / generic MCP client (`mcpServers`):

```json
{
  "mcpServers": {
    "fuin-oni": {
      "command": "python3",
      "args": ["/path/to/fuin-public/mcp/fuin_mcp.py"]
    }
  }
}
```

## Directory manifests

- [`../smithery.yaml`](../smithery.yaml) — Smithery stdio server config.
- [`../server.json`](../server.json) — official MCP registry manifest
  (name + description). A package entry is added when the server is
  published; the registry also requires the `io.github.*` name to match
  the owning GitHub account at publish time.
