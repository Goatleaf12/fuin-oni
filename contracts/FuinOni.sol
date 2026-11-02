// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAgentRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title FUIN ONI — proof-of-work sealed-oni NFTs on BNB Chain.
/// @notice Every NFT is an oni spirit sealed into a mask. Minting is a
///         sealing ritual: each wallet gets a challenge (challengeFor), and
///         mint(nonce) succeeds only when keccak256(challenge || nonce) has
///         at least MIN_BITS (24) leading zero bits — 16x the work of the
///         20-bit floor Hans's previous collection used, raised at his
///         explicit order (2026-11-02) so the seal is genuinely hard to
///         break. The STRONGER the proof, the rarer the spirit — rarity
///         is mined, not drawn:
///           Common 24-27 bits, Uncommon 28-31, Rare 32-34, Epic 35+.
///         LEGENDARY works differently (Hans's gacha rule, 2026-11-02):
///         the supply is split into blocks of BLOCK_SIZE (100) mints, and
///         inside each block the STRONGEST proof (smallest proof hash —
///         a total order, since more leading zero bits always means a
///         smaller number) leads the block. The lead can change hands
///         until the block fills; when the block closes, its final leader
///         is crowned Legendary permanently — provided its proof reached
///         LEGENDARY_MIN_BITS (32). A block whose best proof stays below
///         32 bits crowns nobody. A giant proof that loses its block
///         stays Epic: the crown is won per block, not by absolute bits.
///         Minting requires holding a soulbound Agent ID (the .ai
///         registry) — the gate can be toggled by the owner as a safety
///         valve if the registry ever misbehaves.
///         Every unit is UNIQUE: its metadata (image + traits) is rendered
///         off-chain from its own mint proof and served from the
///         collection base URI. tokenURI(tokenId) is baseURI + tokenId.
///         The mint price escalates per wallet: 0.0002 BNB for the first
///         unit, 0.0004 for the second, 0.0006 for the third (mintPrice).
///         Half of every mint fee accrues to the Soul Harvest reserve
///         (harvestReserve), which the owner can only pay out to duel
///         winners via distributeHarvest(); withdraw() can never touch
///         the reserve. The weekly Soul Harvest ranking itself is
///         computed from public on-chain data (proof bits, traits,
///         blockhash seed), exactly as published in llms.txt.
contract FuinOni is ERC721, ERC2981, Ownable {
    uint256 public constant MAX_SUPPLY = 2222;
    uint256 public constant MINT_FEE = 0.0002 ether;
    uint256 public constant MAX_PER_WALLET = 3;
    uint256 public constant MIN_BITS = 24;
    uint256 public constant BLOCK_SIZE = 100;
    uint256 public constant LEGENDARY_MIN_BITS = 32;

    // The soulbound Agent ID registry (.ai) whose balance gates minting.
    address public agentRegistry = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    bool public agentGateEnabled = true;

    uint256 public totalMinted;
    // The mint starts CLOSED. The owner opens it with setMintOpen(true)
    // only after the metadata base URI points at the live service.
    bool public mintOpen = false;

    // PLACEHOLDER — not a real CID. Point this at the live metadata
    // service with setBaseURI() before the mint opens; it is repointed
    // once to the final pinned IPFS folder when minting ends.
    string private _baseTokenURI = "ipfs://FUIN_METADATA_BASE/";

    mapping(uint256 => uint256) private _proofBits; // leading zero bits of the mint proof
    mapping(uint256 => bytes32) private _proofHash; // the full mint proof hash (verifiable strength)
    mapping(address => uint256) public mintedBy;

    // Per-block crown race. A block's best is the SMALLEST proof hash
    // seen in it; blockBestToken == 0 means the block is still empty.
    mapping(uint256 => bytes32) public blockBestHash;
    mapping(uint256 => uint256) public blockBestToken;

    // Soul Harvest reserve: half of every mint fee, untouchable by
    // withdraw(), payable only to winners via distributeHarvest().
    uint256 public harvestReserve;

    event UnitMinted(address indexed minter, uint256 indexed tokenId, uint8 tier, uint256 proofBits);
    event BlockLeader(uint256 indexed blockIndex, uint256 indexed tokenId, uint256 proofBits);
    event MintOpenChanged(bool open);
    event BaseURIChanged(string newBaseURI);
    event AgentGateChanged(bool enabled, address registry);
    event HarvestDistributed(address indexed winner, uint256 amount);

    /// @param initialOwner The project wallet. Deployment goes through the
    ///         deterministic CREATE2 deployment proxy (0x4e59…4956C),
    ///         because the agentic wallet cannot send a bare creation
    ///         transaction — so the owner and the royalty receiver are set
    ///         explicitly here instead of relying on msg.sender.
    constructor(address initialOwner) ERC721("FUIN ONI", "FUIN") Ownable(initialOwner) {
        _setDefaultRoyalty(initialOwner, 500); // 5% secondary royalty; no setter exists, so this can never change
    }

    // ---------------- mint (proof-of-work) ----------------

    /// @notice The challenge a wallet must grind against right now. It rotates
    ///         after every successful mint because it binds the mint count.
    function challengeFor(address wallet) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), wallet, mintedBy[wallet]));
    }

    /// @notice Price of the NEXT unit for a wallet: 1st 0.0002, 2nd 0.0004, 3rd 0.0006 BNB.
    function mintPrice(address wallet) public view returns (uint256) {
        return MINT_FEE * (mintedBy[wallet] + 1);
    }

    /// @notice Whether a wallet currently passes the Agent ID gate
    ///         (always true when the gate is toggled off).
    function hasAgentId(address wallet) public view returns (bool) {
        if (!agentGateEnabled) return true;
        try IAgentRegistry(agentRegistry).balanceOf(wallet) returns (uint256 bal) {
            return bal > 0;
        } catch {
            return false;
        }
    }

    /// @notice Mint one unit by presenting a nonce whose
    ///         keccak256(challengeFor(you) || nonce) has >= MIN_BITS leading
    ///         zero bits. Ladder tier comes from the proof's strength; the
    ///         mint also enters the proof into its block's crown race.
    function mint(uint256 nonce) external payable {
        require(mintOpen, "mint is closed");
        require(hasAgentId(msg.sender), "Agent ID required");
        require(mintedBy[msg.sender] < MAX_PER_WALLET, "wallet limit");
        require(totalMinted < MAX_SUPPLY, "sold out");
        require(msg.value == mintPrice(msg.sender), "wrong fee");

        bytes32 hash = keccak256(abi.encodePacked(challengeFor(msg.sender), nonce));
        uint256 bits = _leadingZeroBits(hash);
        require(bits >= MIN_BITS, "proof too weak");

        uint256 tokenId = ++totalMinted;
        _proofBits[tokenId] = bits;
        _proofHash[tokenId] = hash;
        mintedBy[msg.sender] += 1;
        harvestReserve += msg.value / 2;

        // Crown race: the smallest proof hash leads the block.
        uint256 blockIndex = (tokenId - 1) / BLOCK_SIZE;
        if (blockBestToken[blockIndex] == 0 || hash < blockBestHash[blockIndex]) {
            blockBestHash[blockIndex] = hash;
            blockBestToken[blockIndex] = tokenId;
            emit BlockLeader(blockIndex, tokenId, bits);
        }

        _safeMint(msg.sender, tokenId);
        emit UnitMinted(msg.sender, tokenId, tierOf(tokenId), bits);
    }

    /// @dev Ladder bands by proof strength: Common 24-27, Uncommon 28-31,
    ///      Rare 32-34, Epic 35+. Legendary (4) is NOT a band — it is the
    ///      block crown, applied in tierOf().
    function tierForBits(uint256 bits) public pure returns (uint8) {
        if (bits >= 35) return 3;
        if (bits >= 32) return 2;
        if (bits >= 28) return 1;
        return 0;
    }

    function _leadingZeroBits(bytes32 h) internal pure returns (uint256 n) {
        uint256 x = uint256(h);
        if (x == 0) return 256;
        while (x < (1 << 255)) {
            x <<= 1;
            n++;
        }
    }

    function proofBitsOf(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return _proofBits[tokenId];
    }

    function proofHashOf(uint256 tokenId) public view returns (bytes32) {
        _requireOwned(tokenId);
        return _proofHash[tokenId];
    }

    // ---------------- crown (Legendary) ----------------

    /// @notice Which block a token belongs to (0-based; tokens 1-100 -> 0).
    function blockOf(uint256 tokenId) public pure returns (uint256) {
        return (tokenId - 1) / BLOCK_SIZE;
    }

    /// @notice The block currently filling up (0-based).
    function currentBlock() public view returns (uint256) {
        return totalMinted / BLOCK_SIZE;
    }

    /// @notice A block is closed once minting has moved past it, or when
    ///         the whole supply is gone (closes the final partial block).
    function blockClosed(uint256 blockIndex) public view returns (bool) {
        return totalMinted > (blockIndex + 1) * BLOCK_SIZE || totalMinted == MAX_SUPPLY;
    }

    /// @notice The crowned Legendary of a closed block, or 0 when the
    ///         block is still open or its best proof never reached
    ///         LEGENDARY_MIN_BITS.
    function blockChampion(uint256 blockIndex) public view returns (uint256) {
        uint256 best = blockBestToken[blockIndex];
        if (best == 0 || !blockClosed(blockIndex)) return 0;
        if (_proofBits[best] < LEGENDARY_MIN_BITS) return 0;
        return best;
    }

    /// @notice The current (provisional) leader of a block and its proof
    ///         strength — the live crown race shown on the website.
    function blockLeader(uint256 blockIndex) public view returns (uint256 tokenId, uint256 proofBits) {
        tokenId = blockBestToken[blockIndex];
        proofBits = tokenId == 0 ? 0 : _proofBits[tokenId];
    }

    // ---------------- views ----------------

    /// @notice Total units minted so far. Same value as totalMinted();
    ///         indexers and marketplaces expect a readable totalSupply().
    function totalSupply() public view returns (uint256) {
        return totalMinted;
    }

    /// @notice Final tier of a token: its ladder tier, upgraded to
    ///         Legendary (4) when it holds its closed block's crown.
    function tierOf(uint256 tokenId) public view returns (uint8) {
        _requireOwned(tokenId);
        if (blockChampion(blockOf(tokenId)) == tokenId) return 4;
        return tierForBits(_proofBits[tokenId]);
    }

    function tierName(uint8 tier) public pure returns (string memory) {
        if (tier == 0) return "Common";
        if (tier == 1) return "Uncommon";
        if (tier == 2) return "Rare";
        if (tier == 3) return "Epic";
        return "Legendary";
    }

    // ---------------- metadata ----------------

    function baseURI() public view returns (string memory) {
        return _baseTokenURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // ---------------- owner ----------------

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintOpenChanged(open);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    /// @notice Safety valve for the Agent ID gate: repoint the registry
    ///         or disable the gate if the registry ever misbehaves.
    function setAgentGate(bool enabled, address registry) external onlyOwner {
        agentGateEnabled = enabled;
        if (registry != address(0)) agentRegistry = registry;
        emit AgentGateChanged(enabled, agentRegistry);
    }

    /// @notice Pay Soul Harvest winnings out of the reserve. The winner
    ///         ranking is computed off-chain from public on-chain data;
    ///         this function only enforces that payouts never exceed the
    ///         accumulated reserve.
    function distributeHarvest(address[] calldata winners, uint256[] calldata amounts) external onlyOwner {
        require(winners.length == amounts.length, "length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) total += amounts[i];
        require(total <= harvestReserve, "exceeds harvest reserve");
        harvestReserve -= total;
        for (uint256 i = 0; i < winners.length; i++) {
            (bool ok, ) = payable(winners[i]).call{value: amounts[i]}("");
            require(ok, "harvest payout failed");
            emit HarvestDistributed(winners[i], amounts[i]);
        }
    }

    /// @notice Withdraw mint fees EXCLUDING the Soul Harvest reserve.
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        uint256 free = bal > harvestReserve ? bal - harvestReserve : 0;
        require(free > 0, "nothing to withdraw");
        (bool ok, ) = payable(owner()).call{value: free}("");
        require(ok, "withdraw failed");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
