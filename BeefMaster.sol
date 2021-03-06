// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import { BaseStrategy, StrategyParams } from "./BaseStrategy.sol";
import { SafeERC20, SafeMath, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import { IBeefVault } from './interfaces/IBeefVault.sol';

//3. Swap for lP tokens

contract BeefMaster is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IBeefVault public BeefVault;

    constructor(address _vault, address _beefVault) public BaseStrategy(_vault) {
        // Instantiate vault
        BeefVault = IBeefVault(_beefVault);
        //approve vault to save gas
        want.safeApprove(_beefVault, type(uint256).max);
        profitFactor = 100;
        debtThreshold = 0;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "GroundBeefBrigade";
    }

    function changeVault(address _vault) external onlyStrategist {
        require(_vault != address(BeefVault), 'Cant change to same vault');

        want.safeDecreaseAllowance(address(BeefVault), type(uint256).max);
        BeefVault = IBeefVault(_vault);
        want.safeApprove(_vault, type(uint256).max);
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    //returns balance of unerlying asset
    function balanceOfVault() public view returns (uint256) {
        return BeefVault.getPricePerFullShare().mul(BeefVault.balanceOf(address(this)));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfVault().add(balanceOfWant());
    }

    //takes underlying and converts it to Beef Vault share price for withdraw
    //@param _amount The amount in the underlying asset needed 
    function toShares(uint256 _amount) internal view returns (uint256) {
        return _amount.div(BeefVault.getPricePerFullShare());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _profit = estimatedTotalAssets();
        _debtPayment = vault.strategies(address(this)).totalDebt;
    }

    //invests available tokens
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // send all of our want tokens to be deposited
        uint256 toInvest = balanceOfWant();
        // stake only if we have something to stake
        if (toInvest > 0) {

            BeefVault.deposit(toInvest);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        //check what we have available
        uint256 wantBalance = balanceOfWant();
        uint256 deposited = balanceOfVault();
        if (_amountNeeded > wantBalance) {
            //if we need more than avaialble find out how much
            uint256 amountToFree = _amountNeeded.sub(wantBalance);

            //check if there is enough in vault
            if (deposited < amountToFree) {
                amountToFree = deposited;
            }
            //withdraw what is needed
            BeefVault.withdraw(toShares(amountToFree));

            //recheck balance of free tokens
            wantBalance = balanceOfWant();

            //check if we got enough tokens from the withdraw
            if (wantBalance >= _amountNeeded) {
                _liquidatedAmount = _amountNeeded;

            } else {
                _liquidatedAmount = wantBalance;
                _loss = _amountNeeded.sub(wantBalance);
        }

            //if we have enough free tokens to start with
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        BeefVault.withdrawAll();

        return balanceOfWant();
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        BeefVault.withdrawAll();

    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = address(BeefVault); 
        
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
