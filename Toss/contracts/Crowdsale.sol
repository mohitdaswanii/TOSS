// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// for anything aboove or equal to 0.8.0, you dont need safemath to do math stuff , overflows are checked by solidity in this version by default
contract Crowdsale is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
	using SafeERC20 for IERC20;

	// keep fundingGaol as a parameter in constructor for changing it later
	uint256 constant fundingGoal = 805 * (10**18);
	/* how much has been raised by crowdale (in BNB) */
	uint256 public amountRaised;
	/* how much has been raised by crowdale (in TOSS) */
	uint256 public amountRaisedTOSS;

	/* the start & end date of the crowdsale */
	uint256 public start;
	uint256 public deadline;
	uint256 public publishDate;

	/* there are different prices in different time intervals */ // if its different then this variable shouldnt be constant
	uint256 constant price = 23238;

	/* the address of the token contract */
	IERC20 private tokenReward;
	/* the balances (in BNB) of all investors */
	mapping(address => uint256) public balanceOf;
	/* the balances (in TOSS) of all investors */
	mapping(address => uint256) public balanceOfTOSS;
	/* indicates if the crowdsale has been closed already */
	mapping(address => bool) public whitelist;
	//change it to isSaleClosed
	bool public saleClosed = false;
	/* notifying transfers and the success of the crowdsale*/
	event GoalReached(address beneficiary, uint256 amountRaised);
	event FundTransfer(address backer, uint256 amount, bool isContribution, uint256 amountRaised);

    /*  initialization, set the token address */
    constructor(IERC20 _token, uint256 _start, uint256 _dead, uint256 _publish) {
        tokenReward = _token;
		start = _start;
		deadline = _dead;
		publishDate = _publish;
    }

	modifier onlyWhitelisted() {
        require(whitelist[_msgSender()] == true, "Caller is not whitelisted");
        _;
    }


    /* invest by sending BNB to the contract. */
    receive () external payable {
		if(msg.sender != owner()) //do not trigger investment if the multisig wallet is returning the funds
        	invest();
		// dont do revert may be have a custom error defined and use it to save gas here, revert would consume all the gas left to the miner
		else revert();
    }

	function updateDeadline(uint256 _dead, uint256 _publish) external onlyOwner {
		// maybe have a check here to confirm the logic of _publish and dead are chronologically correct ?
		deadline = _dead;
		publishDate = _publish;
	}

	function checkFunds(address addr) external view returns (uint256) {
		return balanceOf[addr];
	}

	function checkTOSSFunds(address addr) external view returns (uint256) {
		return balanceOfTOSS[addr];
	}

	// you dont need this
	function getBNBBalance() external view returns (uint256) {
		return address(this).balance;
	}

	function isWhitelisted(address addr) external view returns (bool) {
		return whitelist[addr];
	}

	function addWhitelisted(address addr) external onlyOwner {
		whitelist[addr] = true;
	}

	function removeWhitelisted(address addr) external onlyOwner {
		// delete whiltelist[addr] to save gas or space instead of setting it false
		whitelist[addr] = false;
	}

    /* make an investment
    *  only callable if the crowdsale started and hasn't been closed already and the maxGoal wasn't reached yet.
    *  the current token price is looked up and the corresponding number of tokens is transfered to the receiver.
    *  the sent value is directly forwarded to a safe multisig wallet. // its not sent directly to a multisig wallet in this method
    *  this method allows to purchase tokens in behalf of another address.*/ // its not allowing purchase of tokens on behalf of other address, its using msg.sender to be stored in the mapping
    function invest() public onlyWhitelisted payable {
    	uint256 amount = msg.value;
		require(saleClosed == false && block.timestamp >= start && block.timestamp < deadline, "sale-closed");
		require(msg.value >= 10**15, "less than 0.0001 Eth");

		balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);

		require(balanceOf[msg.sender] <= 5 * 10**18, "more than 5 Eth");

		amountRaised = amountRaised.add(amount);

		balanceOfTOSS[msg.sender] = balanceOfTOSS[msg.sender].add(amount.mul(price));
		amountRaisedTOSS = amountRaisedTOSS.add(amount.mul(price));

		if (amountRaised >= fundingGoal) {
			saleClosed = true;
			emit GoalReached(msg.sender, amountRaised);
		}
		
        emit FundTransfer(msg.sender, amount, true, amountRaised);
    }

    modifier afterClosed() {
		// sale would only be in progress until deadline not publishDate
        require(block.timestamp >= publishDate, "sale-in-progress");
        _;
    }

	function getTOSS() external afterClosed nonReentrant {
		require(balanceOfTOSS[msg.sender] > 0, "non-contribution");
		uint256 amount = balanceOfTOSS[msg.sender];
		uint256 balance = tokenReward.balanceOf(address(this));
		require(balance >= amount, "lack of funds");
		balanceOfTOSS[msg.sender] = 0;
		// consider using safeTransfer method provided by openzeppelin ?
		tokenReward.transfer(msg.sender, amount);
	}

	//if you want to make it transparent,  you can send the money here to a multisig no matter who ever calls this, also add a modifier afterClosed to restrict withdraw until before sale closed
	function withdrawBNB() external onlyOwner {
		uint256 balance = address(this).balance;
		require(balance > 0, "zero-balance");
		address payable payableOwner = payable(owner());
		payableOwner.transfer(balance);
	}

	// think of adding afterclosed if needed
	function withdrawTOSS() external onlyOwner {
		uint256 balance = tokenReward.balanceOf(address(this));
		require(balance > 0, "zero-TOSS-balance");
		tokenReward.transfer(owner(), balance);
	}
}