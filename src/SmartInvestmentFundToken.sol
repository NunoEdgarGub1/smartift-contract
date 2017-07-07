pragma solidity ^0.4.11;
import "Erc20Token.sol";
import "IcoPhaseManagement.sol";
import "Marketplace.sol";

/* The SIFT itself is a simple extension of the ERC20 that allows for granting other SIFT contracts special rights to act on behalf of all transfers. */
contract SmartInvestmentFundToken is Erc20Token("Smart Investment Fund Token", "SIFT", 0) {
    /* Defines the admin contract we interface with for credentails. */
    AuthenticationManager authenticationManager;

    /* Defines the address of the ICO contract which is the only contract permitted to mint tokens. */
    address public icoContractAddress;

    /* Defines the address of the marketplace contract wihich has special permissions to change balances for transaction sales. */
    address public marketplaceContractAddress;

    /* Defines whether or not the fund is closed. */
    bool public isClosed;

    /* Fired when the fund is eventually closed. */
    event FundClosed();

    /* Fired if the marketplace contract is relocated during the ICO phase. */
    event MarketplaceContractRelocated(address addr, uint256 newVersion);

    /* This modifier allows a method to only be called by current admins. */
    modifier adminOnly {
        if (!authenticationManager.isCurrentAdmin(msg.sender)) throw;
        _;
    }
    
    /* Create a new instance of this fund with links to other contracts that are required. */
    function SmartInvestmentFundToken(address _authenticationManagerAddress, address _icoContractAddress, address _marketplaceContractAddress) {
        /* Setup access to our other contracts and validate their versions */
        authenticationManager = AuthenticationManager(_authenticationManagerAddress);
        if (authenticationManager.contractVersion() != 100201707071124)
            throw;
        IcoPhaseManagement icoPhaseManagement = IcoPhaseManagement(_icoContractAddress);
        if (icoPhaseManagement.contractVersion() != 300201707071208)
            throw;
        Marketplace marketplace = Marketplace(_marketplaceContractAddress);
        if (marketplace.contractVersion() != 400201707071240)
            throw;
        
        /* Store our special addresses */
        icoContractAddress = _icoContractAddress;
        marketplaceContractAddress = _marketplaceContractAddress;
    }

    /* Gets the contract version for validation */
    function contractVersion() constant returns(uint256) {
        /* SIFT contract identifies as 500YYYYMMDDHHMM */
        return 500201707071147;
    }

    /* Relocates the marketplace contract to a new address allowing for udpates to the marketplace code during the ICO when marketplace is not yet active. */
    function marketplaceContractRelocate(address _marketplaceContractAddress, uint256 _newVersion) adminOnly {
        /* Check whether ICO has finished, if it has then we have to throw as we are immutable once ICO has ended */
        IcoPhaseManagement icoPhaseManagement = IcoPhaseManagement(icoContractAddress);
        if (!icoPhaseManagement.icoPhase())
            throw;

        /* Check supplied version is in suitable range for marketplace */
        if (_newVersion <= 400201707071240 || _newVersion >= 400201800000000) /* Shouldn't run in to 2018 but this is better than a 5000* cap */
            throw;

        // Check the contract supplied has this version
        Marketplace marketplace = Marketplace(_marketplaceContractAddress);
        if (marketplace.contractVersion() != _newVersion)
            throw;
        
        // Store the changes and audit it
        marketplaceContractAddress = _marketplaceContractAddress;
        MarketplaceContractRelocated(_marketplaceContractAddress, _newVersion);
    }

    /* Mint new tokens - this can only be done by special callers (i.e. the ICO management). */
    function mintTokens(address _address, uint256 _amount) {
        /* Ensure we are the ICO contract calling */
        if (msg.sender != icoContractAddress)
            throw;

        /* Mint the tokens for the new address*/
        bool isNew = balances[_address] < 1;
        balances[_address] += _amount;
        totalSupplyAmount += _amount;
        if (isNew)
            tokenOwnerAdd(_address);
        Transfer(0, _address, _amount);
    }

    /* Transfer shares between owners as part of a marketplace buy/sell operation. */
    function transferShares(address _originalShareholder, address _newShareholder, uint256 _amount) {
        /* Ensure we are the ICO contract calling */
        if (msg.sender != marketplaceContractAddress)
            throw;
        
        /* Transfer ownership of the shares. */
        balances[_originalShareholder] -= _amount;
        bool isBuyerNew = balances[_newShareholder] > 0;
        balances[_newShareholder] += _amount;
        if (isBuyerNew)
            tokenOwnerAdd(_newShareholder);
        if (balances[_originalShareholder] < 1)
            tokenOwnerRemove(_originalShareholder);
        Transfer(_originalShareholder, _newShareholder, _amount);

    }

    /* Handle a balance being reduced - we need to inform the marketplace contract of this so that it can cancel orders as appropriate. */
    function ercReducedBalance(address _from, uint256 _amount) private {
        Marketplace marketplace = Marketplace(marketplaceContractAddress);
        marketplace.notifyBalanceReduced(_from, _amount);
    }

    /* Closes the fund down - this can only happen if the fund has bought back 90% of the shareholding and is designed to be supported by payout of ether matching value to remaining shareholders outside of
       the contract. */
    function closeFund() adminOnly {
        /* Cannot close multiple times */
        if (isClosed)
            throw;

        /* Ensure the shareholder owns required amount of fund */
        Marketplace marketplace = Marketplace(marketplaceContractAddress);
        uint256 requiredAmount = (totalSupplyAmount * 100) / 90;
        if (balances[marketplace.buybackShareholderAccount()] < requiredAmount)
            throw;

        // Zero everyones balances for good measure and shred the coin
        totalSupplyAmount = 0;
        for (uint256 i = 0; i < allTokenHolders.length; i++) {
            address addr = allTokenHolders[i];
            Transfer(allTokenHolders[i], 0, balances[addr]);
            balances[addr] = 0;
        }
        allTokenHolders.length = 0;
        
        /* That's it then, audit and shutdown */
        FundClosed();
        isClosed = true;
    }
}