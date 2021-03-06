//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// You can't import contracts via https from GH. So I just copied these contracts over.
// You could use NPM publish, but this works for now.
import "./CO2KEN_contracts/ToucanCarbonOffsets.sol";
import "./CO2KEN_contracts/pools/BaseCarbonTonne.sol";
import "./CO2KEN_contracts/IToucanContractRegistry.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// what started as a TCO2 faucet has become a faucet for BCT & NCT as well
contract Faucet is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public contractRegistry = 0x6739D490670B2710dc7E79bB12E455DE33EE1cb6;
    address public bctAddress = 0xf2438A14f668b1bbA53408346288f3d7C71c10a1;
    address public nctAddress = 0x7beCBA11618Ca63Ead5605DE235f6dD3b25c530E;
    mapping(address => uint256) private tokenBalances;
    mapping(address => uint256) private lastWithdrawalTimes;
    event Deposited(address erc20Addr, uint256 amount);
    event Withdrawn(address account, address erc20Addr, uint256 amount);

    // @description you can use this to change the TCO2 contracts registry if needed
    // @param _address the contract registry to use
    function setToucanContractRegistry(address _address)
    public
    virtual
    onlyOwner
    {
        contractRegistry = _address;
    }

    function getTokenBalance(address _erc20Address) public view returns (uint256) {
        return tokenBalances[_erc20Address];
    }

    // @description checks if token to be deposited is eligible for this pool
    // @param _erc20Address address to be checked
    function checkTokenEligibility(address _erc20Address)
    private
    view
    returns (bool)
    {
        bool isToucanContract = IToucanContractRegistry(contractRegistry)
        .checkERC20(_erc20Address);
        if (isToucanContract) return true;

        if (_erc20Address == bctAddress) return true;

        if (_erc20Address == nctAddress) return true;

        // nothing matches, return false
        return false;
    }

    /* @notice function to deposit tokens from user to this contract
     * @param _erc20Address ERC20 contract address to be deposited
     * @param _amount amount to be deposited
     */
    function deposit(address _erc20Address, uint256 _amount) public {
        // check token eligibility
        bool eligibility = checkTokenEligibility(_erc20Address);
        require(eligibility, "Token rejected");

        // use TCO contract to do a safe transfer from the user to this contract
        IERC20(_erc20Address).safeTransferFrom(msg.sender, address(this), _amount);

        // add amount of said token to balance sheet of this contract
        tokenBalances[_erc20Address] += _amount;

        // emit an event for good measure
        emit Deposited(_erc20Address, _amount);
    }

    // I decided to have the withdrawal function have a 30s timeout to make sure that nobody spams the faucet.
    //
    // When someone uses it, if the lastWithdrawalTime for their address is not set, it sets it to
    // block.timestamp (right now) - the timeout limit (30s).
    //
    // We then check if the lastWithdrawalTime is less (earlier) than block.timestamp by
    // the timeout limit (30s).
    function checkIfWithdrawalTimeout() public returns (bool) {
        uint256 timeoutLimit = 30; // amount of seconds in between withdrawals
        if (lastWithdrawalTimes[msg.sender] == 0) {
            lastWithdrawalTimes[msg.sender] = block.timestamp - timeoutLimit;
        }
        if (lastWithdrawalTimes[msg.sender] <= block.timestamp - timeoutLimit) {
            return false;
        }
        return true;
    }

    function withdraw(address _erc20Address, uint256 _amount) public {
        // check token eligibility
        bool eligibility = checkTokenEligibility(_erc20Address);
        require(eligibility, "Token rejected");

        // check if the user is in a withdrawal timeout
        require(!checkIfWithdrawalTimeout(), "Cannot withdraw that often");
        lastWithdrawalTimes[msg.sender] = block.timestamp;

        // require that the person didn't request more than the contract has
        require(
            tokenBalances[_erc20Address] >= _amount,
            "Cannot withdraw more than is stored in contract"
        );

        // subtract amount of said token from the balance sheet of this contract
        tokenBalances[_erc20Address] -= _amount;

        // use TCO contract to do a safe transfer from this contract to the user
        IERC20(_erc20Address).safeTransfer(msg.sender, _amount);

        // emit an event for good measure
        emit Withdrawn(msg.sender, _erc20Address, _amount);
    }
}
