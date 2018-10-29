pragma solidity 0.4.25;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract ERC20 {
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function totalSupply() public view returns (uint256);
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function ownerTransfer(address to, uint256 value) public returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function approve(address spender, uint256 value) public returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOfAt(address _owner, uint _blockNumber) public view returns (uint);
    function totalSupplyAt(uint _blockNumber) public view returns(uint);
}


library SafeERC20 {
    function safeTransfer(ERC20 token, address to, uint256 value) internal {
        require(token.transfer(to, value));
    }

    function safeTransferFrom(ERC20 token, address from, address to, uint256 value) internal {
        require(token.transferFrom(from, to, value));
    }

    function safeApprove(ERC20 token, address spender, uint256 value) internal {
        require(token.approve(spender, value));
    }
}


contract Ownable {
    address public owner;
    mapping(address => bool) admins;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AddAdmin(address indexed admin);
    event DelAdmin(address indexed admin);


    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
        admins[owner] = true;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyAdmin() {
        require(isAdmin(msg.sender));
        _;
    }


    function addAdmin(address _adminAddress) external onlyOwner {
        require(_adminAddress != address(0));
        admins[_adminAddress] = true;
        emit AddAdmin(_adminAddress);
    }

    function delAdmin(address _adminAddress) external onlyOwner {
        require(admins[_adminAddress]);
        admins[_adminAddress] = false;
        emit DelAdmin(_adminAddress);
    }

    function isAdmin(address _adminAddress) public view returns (bool) {
        return admins[_adminAddress];
    }
    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0));
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

}


contract HTCDividendManager is Ownable {
    using SafeMath for uint;
    using SafeERC20 for ERC20;

    event DividendDeposited(address indexed _depositor, uint256 _blockNumber, uint256 _amount, uint256 _totalSupply, uint256 _dividendIndex);
    event DividendClaimed(address indexed _claimer, uint256 _dividendIndex, uint256 _claim);
    event DividendRecycled(address indexed _recycler, uint256 _blockNumber, uint256 _amount, uint256 _totalSupply, uint256 _dividendIndex);

    ERC20 public HTCDToken;
    ERC20 public HTCZToken;

    uint256 public RECYCLE_TIME = 30 days;

    struct Dividend {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 amount;
        uint256 claimedAmount;
        uint256 totalSupply;
        bool recycled;
        mapping (address => bool) claimed;
    }

    Dividend[] public dividends;

    mapping (address => uint256) dividendsClaimed;

    modifier validDividendIndex(uint256 _dividendIndex) {
        require(_dividendIndex < dividends.length);
        _;
    }


    constructor (address _HTCDToken, address _HTCZToken) public {
        HTCDToken = ERC20(_HTCDToken);
        HTCZToken = ERC20(_HTCZToken);
    }


    function depositDividend(uint _value) onlyOwner payable public {
        uint256 currentSupply = HTCDToken.totalSupplyAt(block.number);
        uint256 dividendIndex = dividends.length;
        uint256 blockNumber = SafeMath.sub(block.number, 1);
        HTCZToken.safeTransferFrom(msg.sender, this, _value);

        dividends.push(
            Dividend(
                blockNumber,
                getNow(),
                _value,
                0,
                currentSupply,
                false
            )
        );
        emit DividendDeposited(msg.sender, blockNumber, msg.value, currentSupply, dividendIndex);
    }


    function claimDividend(uint256 _dividendIndex) public
    validDividendIndex(_dividendIndex)
    {
        Dividend storage dividend = dividends[_dividendIndex];
        require(dividend.claimed[msg.sender] == false);
        require(dividend.recycled == false);
        uint256 balance = HTCDToken.balanceOfAt(msg.sender, dividend.blockNumber);
        uint256 claim = balance.mul(dividend.amount).div(dividend.totalSupply);
        dividend.claimed[msg.sender] = true;
        dividend.claimedAmount = SafeMath.add(dividend.claimedAmount, claim);
        if (claim > 0) {
            HTCZToken.safeTransfer(msg.sender, claim);
            emit DividendClaimed(msg.sender, _dividendIndex, claim);
        }
    }

    function claimDividendAll() public {
        require(dividendsClaimed[msg.sender] < dividends.length);
        for (uint i = dividendsClaimed[msg.sender]; i < dividends.length; i++) {
            if ((dividends[i].claimed[msg.sender] == false) && (dividends[i].recycled == false)) {
                dividendsClaimed[msg.sender] = SafeMath.add(i, 1);
                claimDividend(i);
            }
        }
    }

    function recycleDividend(uint256 _dividendIndex) public onlyOwner validDividendIndex(_dividendIndex)
    {
        Dividend storage dividend = dividends[_dividendIndex];
        require(dividend.recycled == false);
        require(dividend.timestamp < SafeMath.sub(getNow(), RECYCLE_TIME));
        dividends[_dividendIndex].recycled = true;
        uint256 currentSupply = HTCDToken.totalSupplyAt(block.number);
        uint256 remainingAmount = SafeMath.sub(dividend.amount, dividend.claimedAmount);
        uint256 dividendIndex = dividends.length;
        uint256 blockNumber = SafeMath.sub(block.number, 1);
        dividends.push(
            Dividend(
                blockNumber,
                getNow(),
                remainingAmount,
                0,
                currentSupply,
                false
            )
        );
        emit DividendRecycled(msg.sender, blockNumber, remainingAmount, currentSupply, dividendIndex);
    }

    //Function is mocked for tests
    function getNow() internal constant returns (uint256) {
        return now;
    }

}