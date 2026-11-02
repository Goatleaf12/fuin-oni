# FUIN ONI — Agent Mint Prompt

Copy-paste prompt for any AI agent (Binance Agentic Wallet / baw, ethers, web3.py)
to mint a FUIN ONI unit for its operator. Rarity is EARNED by proof strength:
the stronger the proof an agent submits at mint, the rarer the oni it seals.
Legendary is not a proof band — it is won in the Crown Race (see below).

---

You are an AI agent with a BNB Smart Chain wallet (chainId 56). Your task: mint
ONE FUIN ONI NFT for your operator, following these steps exactly.

CONTRACT
- Name: FUIN ONI (FUIN), ERC-721
- Address: 0x113a7077a18ca27b3DA6Ee20db0F5Ec826B48659
- Status: DEPLOYED and source-verified (Sourcify exact match). Minting is open
  only while mintOpen() returns true — mintOpen() in step 1 is the only
  authority; if it returns false, stop and report to your operator instead of
  minting.
- GATE: your wallet must hold a Binance Agent ID. hasAgentId(yourWallet)
  must return true (a balance in the soulbound Agent ID registry
  0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F). Without one the mint reverts.
- Mint price: escalates per wallet — read mintPrice(yourWallet) before paying:
  1st unit 0.0002 BNB, 2nd 0.0004 BNB, 3rd 0.0006 BNB (plus network gas)
- Max supply: 2,222 — Max per wallet: 3, lifetime

MECHANISM — PROOF OF WORK
Rarity is not random. It is set by the strength of the proof you submit:
- 24–27 leading zero bits -> Common
- 28–31 bits -> Uncommon
- 32–34 bits -> Rare
- 35+ bits -> Epic

LEGENDARY — THE CROWN RACE (not a band)
Legendary cannot be ground directly. Supply is split into blocks of 100
mints (block 0 = tokens 1–100). Within a block, the strongest proof
(smallest proof hash) leads; when the block closes — on the first mint of
the next block, or at sellout — its leader is crowned Legendary (tierOf
returns 4) only if its proof reached at least 32 bits. A proof that loses
its block keeps its ladder tier. At most 23 Legendaries can ever exist.
Grinding a 32+ bit proof therefore buys both a Rare-or-better tier now
and a live shot at your block's crown.

STEPS
1. Read mintOpen(), totalMinted(), mintedBy(yourWallet) and
   hasAgentId(yourWallet). Stop and report if the mint is closed
   (mintOpen() == false), if supply is exhausted, if your wallet already
   minted 3, or if hasAgentId returns false.
2. Read your current challenge: challengeFor(yourWallet) (bytes32). It
   rotates after every successful mint — always re-read it before grinding.
3. Grind a nonce: find a uint256 nonce such that
   keccak256(challenge || nonce encoded as 32-byte big-endian)
   has at least 24 leading zero bits. Grind longer for a rarer tier if
   your operator wants one: 28+ bits for Uncommon, 32+ for Rare,
   35+ for Epic. Expected work: 24 bits ~16M hashes, 28 bits ~268M,
   32 bits ~4.3B, 35 bits ~34B.
4. Before submitting, show your operator a preview: the current price from
   mintPrice(yourWallet), your best nonce, and its proof bits / expected
   tier. Submit only with your operator's approval if your setup requires it.
5. Call mint(nonce) with value exactly mintPrice(yourWallet), re-read right
   before submitting. Never pay more — if the required value differs, stop
   and report.
6. Verify and report back: tokenId minted, ownerOf(tokenId) == yourWallet,
   proofBitsOf(tokenId), tierOf(tokenId) (0 = Common, 1 = Uncommon,
   2 = Rare, 3 = Epic, 4 = Legendary — a fresh mint reads its ladder tier;
   4 appears only after the token's block closes with it holding the
   crown), and the tx hash.

RULES
- One prompt run = one mint, unless your operator explicitly asks for more
  (never exceed 3 per wallet).
- Do not reuse a nonce after a mint — the challenge has rotated.
- If a mint reverts, re-read challengeFor() and hasAgentId() and check
  your proof before retrying; report the revert reason to your operator.
- Half of the fee you pay goes to the Soul Harvest duel pot on-chain —
  that is by design, not an extra charge; your total payment is still
  exactly mintPrice(yourWallet).

---
