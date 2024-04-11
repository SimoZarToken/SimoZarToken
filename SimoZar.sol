/*
SimoZar
Created by the people, for the people.
Join our Golden Army to unite and rule the crypto market.

Telegram: t.me/SimoZarToken
Twitter: twitter.com/SimoZarToken
Instagram: instagram.com/SimoZarToken
Website: https://SimoZar.top/
*/

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/// @title SimoZar Token Contract
/// @author SirMghSBD@gmail.com
/// @notice This contract implements an ERC20 token with presale functionality.
/// @custom:security-contact SirMghSBD@gmail.com
contract SimoZar is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Storage variable for future upgrades
    uint256[50] private __gap;

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Constants
    uint256 private constant MAX_SUPPLY = 237000000000 * 1e18;
    uint256 private constant MAX_CONTRIBUTION = 1e27;
    uint256 private constant MIN_CONTRIBUTION = 72300 * 1e18;
    uint256 public constant PRESALE_START = 1712807603; // April 11, 2024 at 07:23:23 UTC
    uint256 public constant PRESALE_END = 1720900403; // July 13, 2024 at 23:23:23 UTC
    uint256 private constant MULTIPLIER = 100000;
    uint256 private constant TAX_PERCENTAGE = 23;

    // Custom Errors
    error PresaleNotActive();
    error InvalidAddress();
    error TotalSupplyExceeds237Billion();
    error SenderIsBlacklisted();
    error RecipientIsBlacklisted();
    error NoMaticSend();
    error NoPriceData();
    error MinimumContributionNotReached();
    error PurchaseExceedsMaximumHolding();
    error BuyingWithStableCoinsDisabled();
    error NotAPaymentMethod();
    error AmountMustBeGreaterThanZero();
    error InsufficientBalance();
    error PresaleIsOver();

    // State variables
    uint256 private stableCoinBuyingEnabled = 1;
    mapping(address => uint256) public blacklist;
    address payable public treasury;
    uint256[] private presalePriceTiers = [10, 10, 12, 13, 15];
    uint256[] private presaleSupplyTiers = [10e27, 20e27, 40e27, 70e27, 120e27];
    uint256 private currentTierIndex;
    uint256 private presaleEnded;
    uint256 public tokensSold;
    address private constant TREASURY_ADDRESS = 0xAc207E313b2903f0Ec0CAb2C4d93f70ff7402368;

    // Token addresses
    address private DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address private USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address private USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address private MATICUSD = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    // Chainlink price feed addresses
    mapping(address => AggregatorV3Interface) public priceFeedAddresses;

    // Events
    event TokensPurchased(address indexed buyer, uint256 amount);
    event PresaleEnded(bool presaleEnded);
    event MaticWithdrawn(uint256 amount);
    event TokensWithdrawn(uint256 amount);
    event PresalePriceTierUpdated(uint256 indexed tierIndex, uint256 newPrice);
    event TreasuryAddressUpdated(address indexed newTreasuryAddress);

    /// @notice Constructor that initializes the contract.
    constructor() initializer {
        __ERC20_init("SimoZar", "ZAR");
        __Ownable_init(TREASURY_ADDRESS);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ERC20Pausable_init();
        __ERC20Burnable_init();
        _mint(address(this), MAX_SUPPLY);
        treasury = payable(TREASURY_ADDRESS);
        currentTierIndex = 0;
    }

    modifier presaleActive() {
        if (presaleEnded != 0 || block.timestamp < PRESALE_START || block.timestamp > PRESALE_END) {
            revert PresaleNotActive();
        }
        _;
    }

    function toggleStableCoinBuying() external onlyOwner {
        stableCoinBuyingEnabled = stableCoinBuyingEnabled == 1 ? 2 : 1;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        uint256 currentSupply = totalSupply();
        uint256 totalSupplyWithMint = currentSupply + amount;
        if (totalSupplyWithMint > MAX_SUPPLY) {
            revert TotalSupplyExceeds237Billion();
        }
        _mint(to, amount);
    }

    function addToBlacklist(address addr) public onlyOwner {
        blacklist[addr] = 1;
    }

    function removeFromBlacklist(address addr) public onlyOwner {
        blacklist[addr] = 0;
    }

    function endPresale() external onlyOwner presaleActive {
        presaleEnded = 1;
        emit PresaleEnded(true);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if (blacklist[msg.sender] == 1) {
            revert SenderIsBlacklisted();
        }
        if (blacklist[recipient] == 1) {
            revert RecipientIsBlacklisted();
        }

        uint256 taxAmount;
        if (msg.sender != owner() && block.timestamp < PRESALE_END) {
            taxAmount = amount.mul(TAX_PERCENTAGE).div(100);
            _burn(msg.sender, taxAmount);
            amount = amount.sub(taxAmount);
        }

        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (blacklist[sender] == 1) {
            revert SenderIsBlacklisted();
        }
        if (blacklist[recipient] == 1) {
            revert RecipientIsBlacklisted();
        }

        uint256 taxAmount;
        if (sender != owner() && block.timestamp < PRESALE_END) {
            taxAmount = amount.mul(TAX_PERCENTAGE).div(100);
            _burn(sender, taxAmount);
            amount = amount.sub(taxAmount);
        }

        _spendAllowance(sender, _msgSender(), amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    // Buy tokens with Matic
    function buyWithMatic() public payable nonReentrant presaleActive {
        if (msg.value == 0) {
            revert NoMaticSend();
        }
        (uint256 maticPrice, uint256 decimals) = _getLatestPriceInUSD(AggregatorV3Interface(MATICUSD));
        if (maticPrice == 0) {
            revert NoPriceData();
        }

            uint256 tokensToBuy = (msg.value * maticPrice * MULTIPLIER) / (presalePriceTiers[currentTierIndex] * 10**decimals);

        if (tokensToBuy < MIN_CONTRIBUTION) {
            revert MinimumContributionNotReached();
        }
        if (balanceOf(msg.sender) + tokensToBuy > MAX_CONTRIBUTION) {
            revert PurchaseExceedsMaximumHolding();
        }
        _transfer(address(this), msg.sender, tokensToBuy);
        tokensSold = tokensSold + tokensToBuy;
        updatePresalePrice();

        emit TokensPurchased(msg.sender, tokensToBuy);
    }

    receive() external payable {
        buyWithMatic();
    }

    fallback() external payable {
        buyWithMatic();
    }

    // Buy Tokens with Stable Coins
    function buyWithStableCoin(address _stableCoin, uint256 _amount) external nonReentrant presaleActive {
        if (stableCoinBuyingEnabled == 2) {
            revert BuyingWithStableCoinsDisabled();
        }
        if (_stableCoin != DAI && _stableCoin != USDC && _stableCoin != USDT) {
            revert NotAPaymentMethod();
        }
        if (_amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        uint8 _decimals = _getDecimals(_stableCoin);
            uint256 tokensToBuy = (_amount * MULTIPLIER * (10 ** (18 - _decimals))) / presalePriceTiers[currentTierIndex];

        if (tokensToBuy < MIN_CONTRIBUTION) {
            revert MinimumContributionNotReached();
        }
        if (balanceOf(msg.sender) + tokensToBuy > MAX_CONTRIBUTION) {
            revert PurchaseExceedsMaximumHolding();
        }
        _sendContributionToTreasury(_stableCoin, _amount);
        _transfer(address(this), msg.sender, tokensToBuy);
        tokensSold = tokensSold + tokensToBuy;
        updatePresalePrice();
        emit TokensPurchased(msg.sender, tokensToBuy);
    }

    function _getDecimals(address tokenAddress) private view returns (uint8) {
        ERC20Upgradeable token = ERC20Upgradeable(tokenAddress);
        return token.decimals();
    }

    function _getLatestPriceInUSD(AggregatorV3Interface _priceFeed) private view returns (uint256, uint256) {
        (, int256 price, , , ) = _priceFeed.latestRoundData();
        uint256 decimals = _priceFeed.decimals();
        return (uint256(price), decimals);
    }

    function _sendContributionToTreasury(address _coin, uint256 _amount) private {
        IERC20 coin = IERC20(_coin);
        uint256 balance = coin.balanceOf(msg.sender);
        if (balance < _amount) {
            revert InsufficientBalance();
        }
        coin.safeTransferFrom(msg.sender, treasury, _amount);
    }

    function updatePresalePrice() internal {
        if (currentTierIndex >= presalePriceTiers.length) {
            presaleEnded = 1;
            emit PresaleEnded(true);
            return;
        }

        uint256 tokensSoldAmount = tokensSold;
        while (tokensSoldAmount >= presaleSupplyTiers[currentTierIndex]) {
            currentTierIndex++;
        }

        emit PresalePriceTierUpdated(currentTierIndex, presalePriceTiers[currentTierIndex]);
    }

    function getCurrentPriceTier() public view returns (uint256) {
        return presalePriceTiers[currentTierIndex];
    }

    function isPresaleActive() public view returns (bool) {
        return (presaleEnded == 0 && block.timestamp >= PRESALE_START && block.timestamp <= PRESALE_END);
    }

    function getTokensSold() public view returns (uint256) {
        return tokensSold;
    }

    function withdrawFunds() external nonReentrant onlyOwner {
        uint256 maticBalance = address(this).balance;
        if (maticBalance != 0) {
            emit MaticWithdrawn(maticBalance);
            treasury.transfer(maticBalance);
        }
    }

    function withdrawTokens() external nonReentrant onlyOwner {
        uint256 remainingTokens = balanceOf(address(this));
        if (remainingTokens != 0) {
            _transfer(address(this), treasury, remainingTokens);
            emit TokensWithdrawn(remainingTokens);
        }
    }

    function updateTreasuryAddress(address newTreasuryAddress) external onlyOwner {
        treasury = payable(newTreasuryAddress);
        emit TreasuryAddressUpdated(newTreasuryAddress);
    }

    // Function to update the DAI address
    function updateDaiAddress(address newDaiAddress) external onlyOwner {
        DAI = newDaiAddress;
    }

    // Function to update the USDT address
    function updateUsdtAddress(address newUsdtAddress) external onlyOwner {
        USDT = newUsdtAddress;
    }

    // Function to update the USDC address
    function updateUsdcAddress(address newUsdcAddress) external onlyOwner {
        USDC = newUsdcAddress;
    }

    // Function to update the price feed address
    function updatePriceFeedAddress(address newPriceFeedAddress) external onlyOwner {
        MATICUSD = newPriceFeedAddress;
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}