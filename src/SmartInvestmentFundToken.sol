pragma solidity ^0.4.11;
import "Erc20Token.sol";
import "IcoPhaseManagement.sol";

/* The SIFT itself is a simple extension of the ERC20 that allows for granting other SIFT contracts special rights to act on behalf of all transfers. */
contract SmartInvestmentFundToken is Erc20Token("Smart Investment Fund Token", "SIFT", 0) {
    /* Defines the admin contract we interface with for credentails. */
    AuthenticationManager authenticationManager;

    /* Defines the address of the ICO contract which is the only contract permitted to mint tokens. */
    address public icoContractAddress;

    /* Defines whether or not the fund is closed. */
    bool public isClosed;

    /* Defines the contract handling the ICO phase. */
    IcoPhaseManagement icoPhaseManagement;

    /* Fired when the fund is eventually closed. */
    event FundClosed();

    /* This modifier allows a method to only be called by current admins. */
    modifier adminOnly {
        if (!authenticationManager.isCurrentAdmin(msg.sender)) throw;
        _;
    }
    
    /* Create a new instance of this fund with links to other contracts that are required. */
    function SmartInvestmentFundToken(address _authenticationManagerAddress, address _icoContractAddress) {
        /* Setup access to our other contracts and validate their versions */
        authenticationManager = AuthenticationManager(_authenticationManagerAddress);
        if (authenticationManager.contractVersion() != 100201707071124)
            throw;
        icoPhaseManagement = IcoPhaseManagement(_icoContractAddress);
        if (icoPhaseManagement.contractVersion() != 300201707071208)
            throw;
        
        /* Store our special addresses */
        icoContractAddress = _icoContractAddress;
    }

    /* Gets the contract version for validation */
    function contractVersion() constant returns(uint256) {
        /* SIFT contract identifies as 500YYYYMMDDHHMM */
        return 500201707071147;
    }

    /* Mint new tokens - this can only be done by special callers (i.e. the ICO management) during the ICO phase. */
    function mintTokens(address _address, uint256 _amount) {
        /* Ensure we are the ICO contract calling */
        if (msg.sender != icoContractAddress || !icoPhaseManagement.icoPhase())
            throw;

        /* Mint the tokens for the new address*/
        bool isNew = balances[_address] == 0;
        balances[_address] += _amount;
        totalSupplyAmount += _amount;
        if (isNew)
            tokenOwnerAdd(_address);
        Transfer(0, _address, _amount);
    }
}