// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HarbergerNFTs is ERC721, ReentrancyGuard {
    address public treasurer;
    uint256 public MAX_PRICE; // set in constructor
    uint256 public MIN_PRICE; // set in constructor
    uint256 public GLOBAL_TAX_RATE; // global tax rate in basis points, where max == 100% = 10_000
    uint256 public Cliff; // number seconds after minting/modification that tax MUST be paid or face default

    // NFT metadata mappings
    mapping(uint256 => uint256) public nftPrices; // tokenId => price
    mapping(uint256 => uint64) public nftTimestamps; // tokenId => timestamp of last modification
    mapping(uint256 => bool) public defaultedNFTs; // tokenId => whether NFT is defaulted

    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant BASIS_POINTS = 10_000;
    uint256 private constant BLOCK_TIME_MARGIN = 25; // 24 + 1 seconds for 2 blocks
    uint256 private constant SCALING_FACTOR = 1e18; // Used to prevent rounding errors in tax calculations

    event NewCliffSet(uint256 indexed newCliff);
    event NFTMinted(uint256 indexed tokenId, address indexed owner, uint256 price);
    event NFTModified(uint256 indexed tokenId, address indexed owner, uint256 newPrice);
    event NFTPurchased(uint256 indexed tokenId, address indexed from, address indexed to, uint256 price);
    event NFTDefaulted(uint256 indexed tokenId, address indexed previousOwner);
    event TaxPaid(uint256 indexed tokenId, address indexed payer, uint256 amount);

    error InvalidPrice();
    error InvalidTaxRate();
    error InvalidCliff();
    error InvalidToken();
    error InvalidTreasurer();
    error TokenDefaulted();
    error NotOwner();
    error InsufficientPayment();
    error BlockTimeMarginNotMet();
    error ZeroAddress();

    modifier blockTimeMargin(uint256 tokenId) {
        uint64 lastTimestamp = nftTimestamps[tokenId];
        if (lastTimestamp == 0) {
            revert InvalidPrice();
        }
        if (block.timestamp < lastTimestamp + BLOCK_TIME_MARGIN) {
            revert BlockTimeMarginNotMet();
        }
        _;
    }

    constructor(
        address _treasurer,
        uint256 _maxPrice,
        uint256 _minPrice,
        uint256 _globalTaxRate,
        uint256 _cliff,
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        if (_treasurer == address(0)) revert ZeroAddress();
        if (_maxPrice > 1e18) revert InvalidPrice();
        if (_minPrice < 0.001 ether) revert InvalidPrice();
        if (_globalTaxRate > BASIS_POINTS) revert InvalidTaxRate();
        if (_cliff < 2628002) revert InvalidCliff(); // set at 1 month, but should be carefully set during contract deployment

        treasurer = _treasurer;
        MAX_PRICE = _maxPrice;
        MIN_PRICE = _minPrice;
        GLOBAL_TAX_RATE = _globalTaxRate;
        Cliff = _cliff;
    }

    function mint(address to, uint256 tokenId, uint256 value) external {
        if (to == address(0)) revert ZeroAddress();
        if (value == 0 || value < MIN_PRICE || value > MAX_PRICE) revert InvalidPrice();
        if (_ownerOf(tokenId) != address(0)) revert InvalidToken();

        _mint(to, tokenId);
        nftPrices[tokenId] = value;
        nftTimestamps[tokenId] = uint64(block.timestamp);

        emit NFTMinted(tokenId, to, value);
    }

    function modify(uint256 tokenId, uint256 newPrice) external payable nonReentrant blockTimeMargin(tokenId) {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (defaultedNFTs[tokenId]) revert TokenDefaulted();
        if (newPrice == 0 || newPrice < MIN_PRICE || newPrice > MAX_PRICE) revert InvalidPrice();

        uint256 taxDue = returnTaxDue(tokenId);
        nftPrices[tokenId] = newPrice;
        nftTimestamps[tokenId] = uint64(block.timestamp);

        if (taxDue > 0) {
            (bool success,) = payable(treasurer).call{value: taxDue}("");
            require(success, "Tax payment failed");
            emit TaxPaid(tokenId, msg.sender, taxDue);
        }

        emit NFTModified(tokenId, msg.sender, newPrice);
    }

    function purchase(uint256 tokenId) external payable nonReentrant blockTimeMargin(tokenId) {
        if (defaultedNFTs[tokenId]) revert TokenDefaulted();

        address currentOwner = ownerOf(tokenId);
        if (currentOwner == address(0)) revert ZeroAddress();

        uint256 price = nftPrices[tokenId];
        uint256 taxDue = returnTaxDue(tokenId);
        uint256 totalRequired = price + taxDue;

        if (msg.value < totalRequired) revert InsufficientPayment();
        // CEI
        _transfer(currentOwner, msg.sender, tokenId);
        nftTimestamps[tokenId] = uint64(block.timestamp);
        // pay price to owner
        (bool success1,) = payable(currentOwner).call{value: price}("");
        require(success1, "Payment to owner failed");
        // pay tax to treasury
        if (taxDue > 0) {
            (bool success2,) = payable(treasurer).call{value: taxDue}("");
            require(success2, "Tax payment failed");
            emit TaxPaid(tokenId, msg.sender, taxDue);
        }
        // refund excess
        if (msg.value > totalRequired) {
            (bool success3,) = payable(msg.sender).call{value: msg.value - totalRequired}("");
            require(success3, "Refund failed");
        }
        emit NFTPurchased(tokenId, currentOwner, msg.sender, price);
    }

    function evaluateAndAddress(uint256 tokenId) public nonReentrant returns (bool) {
        if (defaultedNFTs[tokenId]) return true;

        uint64 lastTimestamp = nftTimestamps[tokenId];
        if (lastTimestamp == 0) revert("Token does not exist"); // check for condition where token doesn't exist

        uint256 timeElapsed = block.timestamp - lastTimestamp;

        // check if cliff has elapsed (with 2 block margins)
        if (timeElapsed >= Cliff + BLOCK_TIME_MARGIN) {
            // NFT has defaulted - repossess to treasury - and NO REFUND provided
            address currentOwner = ownerOf(tokenId);
            _transfer(currentOwner, treasurer, tokenId);
            defaultedNFTs[tokenId] = true;
            emit NFTDefaulted(tokenId, currentOwner);
            return true;
        }
        return false;
    }

    function returnTaxDue(uint256 tokenId) public view returns (uint256 taxDue) {
        if (defaultedNFTs[tokenId]) return 0;

        uint64 lastTimestamp = nftTimestamps[tokenId];
        if (lastTimestamp == 0) return 0;

        uint256 price = nftPrices[tokenId];
        uint256 timeElapsed = block.timestamp - lastTimestamp;
        taxDue = (price * GLOBAL_TAX_RATE * timeElapsed * SCALING_FACTOR) / (SECONDS_PER_YEAR * BASIS_POINTS);
        taxDue = taxDue / SCALING_FACTOR;
    }

    function payTax(uint256 tokenId) external payable nonReentrant {
        if (defaultedNFTs[tokenId]) revert TokenDefaulted();

        // require caller is NFT owner
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        uint256 taxDue = returnTaxDue(tokenId);
        if (msg.value < taxDue) revert InsufficientPayment();

        // CEI
        nftTimestamps[tokenId] = uint64(block.timestamp);

        (bool success,) = payable(treasurer).call{value: taxDue}("");
        require(success, "Tax payment failed");

        if (msg.value > taxDue) {
            (bool success2,) = payable(msg.sender).call{value: msg.value - taxDue}("");
            require(success2, "Refund failed");
        }

        emit TaxPaid(tokenId, msg.sender, taxDue);
    }

    function getPrice(uint256 tokenId) external view returns (uint256) {
        return nftPrices[tokenId];
    }

    function getTimestamp(uint256 tokenId) external view returns (uint64) {
        return nftTimestamps[tokenId];
    }

    function isDefaulted(uint256 tokenId) external view returns (bool) {
        return defaultedNFTs[tokenId];
    }
}
