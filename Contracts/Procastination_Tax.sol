// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 */
abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 */
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

/**
 * @title ProcrastinationTax
 * @dev DeFi protocol that charges users more the longer they delay transactions
 * @author Smart Contract Developer
 */
contract ProcrastinationTax is ReentrancyGuard, Ownable {
    
    // Struct to store pending transaction details
    struct PendingTransaction {
        address user;
        uint256 amount;
        uint256 createdAt;
        uint256 baseRate;
        bool executed;
        string transactionType;
    }
    
    // State variables
    mapping(bytes32 => PendingTransaction) public pendingTransactions;
    mapping(address => bytes32[]) public userTransactions;
    mapping(address => uint256) public userBalances;
    
    // Protocol parameters
    uint256 public constant BASE_TAX_RATE = 100; // 1% per day (100 basis points)
    uint256 public constant MAX_TAX_RATE = 5000; // 50% maximum
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public totalCollectedTax;
    
    // Events
    event TransactionScheduled(
        bytes32 indexed txId, 
        address indexed user, 
        uint256 amount, 
        string txType
    );
    
    event TransactionExecuted(
        bytes32 indexed txId, 
        address indexed user, 
        uint256 originalAmount, 
        uint256 taxAmount, 
        uint256 finalAmount
    );
    
    event TaxCollected(address indexed user, uint256 taxAmount);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Schedule a transaction that will accumulate tax over time
     * @param amount The amount for the transaction
     * @param txType Type of transaction (e.g., "withdrawal", "swap", "stake")
     */
    function scheduleTransaction(
        uint256 amount, 
        string memory txType
    ) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(msg.value >= amount, "Insufficient ETH sent");
        
        // Generate unique transaction ID
        bytes32 txId = keccak256(
            abi.encodePacked(
                msg.sender, 
                amount, 
                block.timestamp, 
                block.number
            )
        );
        
        // Store the transaction
        pendingTransactions[txId] = PendingTransaction({
            user: msg.sender,
            amount: amount,
            createdAt: block.timestamp,
            baseRate: BASE_TAX_RATE,
            executed: false,
            transactionType: txType
        });
        
        // Update user's transaction list
        userTransactions[msg.sender].push(txId);
        
        // Update user balance (excess ETH)
        if (msg.value > amount) {
            userBalances[msg.sender] += msg.value - amount;
        }
        
        emit TransactionScheduled(txId, msg.sender, amount, txType);
    }
    
    /**
     * @dev Execute a scheduled transaction with accumulated procrastination tax
     * @param txId The transaction ID to execute
     */
    function executeTransaction(bytes32 txId) external nonReentrant {
        PendingTransaction storage txn = pendingTransactions[txId];
        
        require(txn.user == msg.sender, "Not authorized");
        require(!txn.executed, "Transaction already executed");
        require(txn.amount > 0, "Invalid transaction");
        
        // Calculate procrastination tax
        uint256 taxAmount = calculateProcrastinationTax(txId);
        uint256 finalAmount = txn.amount;
        
        if (taxAmount > 0) {
            require(taxAmount < txn.amount, "Tax exceeds transaction amount");
            finalAmount = txn.amount - taxAmount;
            totalCollectedTax += taxAmount;
            emit TaxCollected(msg.sender, taxAmount);
        }
        
        // Mark as executed
        txn.executed = true;
        
        // Transfer the final amount to user
        (bool success, ) = payable(msg.sender).call{value: finalAmount}("");
        require(success, "Transfer failed");
        
        emit TransactionExecuted(txId, msg.sender, txn.amount, taxAmount, finalAmount);
    }
    
    /**
     * @dev Calculate the procrastination tax for a given transaction
     * @param txId The transaction ID
     * @return The calculated tax amount
     */
    function calculateProcrastinationTax(bytes32 txId) public view returns (uint256) {
        PendingTransaction memory txn = pendingTransactions[txId];
        
        if (txn.executed || txn.amount == 0) {
            return 0;
        }
        
        // Calculate days since transaction was scheduled
        uint256 daysPassed = (block.timestamp - txn.createdAt) / SECONDS_PER_DAY;
        
        if (daysPassed == 0) {
            return 0; // No tax for same-day execution
        }
        
        // Calculate exponential tax rate: base_rate * days^1.5
        uint256 taxRate = txn.baseRate * daysPassed * sqrt(daysPassed);
        
        // Cap at maximum tax rate
        if (taxRate > MAX_TAX_RATE) {
            taxRate = MAX_TAX_RATE;
        }
        
        // Calculate tax amount (tax rate in basis points)
        return (txn.amount * taxRate) / 10000;
    }
    
    /**
     * @dev Helper function for square root calculation using Babylonian method
     * @param x The number to calculate square root for
     * @return The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
        if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
        if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
        if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
        if (xx >= 0x100) { xx >>= 8; r <<= 4; }
        if (xx >= 0x10) { xx >>= 4; r <<= 2; }
        if (xx >= 0x8) { r <<= 1; }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
    
    /**
     * @dev Get all transaction IDs for a specific user
     * @param user The user address
     * @return Array of transaction IDs
     */
    function getUserTransactions(address user) external view returns (bytes32[] memory) {
        return userTransactions[user];
    }
    
    /**
     * @dev Get detailed information about a specific transaction
     * @param txId The transaction ID
     * @return user The transaction owner
     * @return amount The transaction amount
     * @return createdAt The creation timestamp
     * @return currentTax The current tax amount
     * @return executed Whether the transaction has been executed
     * @return txType The transaction type
     */
    function getTransactionDetails(bytes32 txId) external view returns (
        address user,
        uint256 amount,
        uint256 createdAt,
        uint256 currentTax,
        bool executed,
        string memory txType
    ) {
        PendingTransaction memory txn = pendingTransactions[txId];
        return (
            txn.user,
            txn.amount,
            txn.createdAt,
            calculateProcrastinationTax(txId),
            txn.executed,
            txn.transactionType
        );
    }
    
    /**
     * @dev Get the number of days passed since transaction creation
     * @param txId The transaction ID
     * @return Number of days passed
     */
    function getDaysPassed(bytes32 txId) external view returns (uint256) {
        PendingTransaction memory txn = pendingTransactions[txId];
        if (txn.createdAt == 0) return 0;
        return (block.timestamp - txn.createdAt) / SECONDS_PER_DAY;
    }
    
    /**
     * @dev Get the current tax rate for a transaction (in basis points)
     * @param txId The transaction ID
     * @return The current tax rate
     */
    function getCurrentTaxRate(bytes32 txId) external view returns (uint256) {
        PendingTransaction memory txn = pendingTransactions[txId];
        if (txn.executed || txn.amount == 0) return 0;
        
        uint256 daysPassed = (block.timestamp - txn.createdAt) / SECONDS_PER_DAY;
        if (daysPassed == 0) return 0;
        
        uint256 taxRate = txn.baseRate * daysPassed * sqrt(daysPassed);
        return taxRate > MAX_TAX_RATE ? MAX_TAX_RATE : taxRate;
    }
    
    /**
     * @dev Owner function to withdraw collected taxes
     */
    function withdrawCollectedTax() external onlyOwner {
        uint256 amount = totalCollectedTax;
        require(amount > 0, "No tax to withdraw");
        totalCollectedTax = 0;
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdrawal failed");
    }
    
    /**
     * @dev Allow users to withdraw their excess ETH balance
     */
    function withdrawUserBalance() external nonReentrant {
        uint256 balance = userBalances[msg.sender];
        require(balance > 0, "No balance to withdraw");
        
        userBalances[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    /**
     * @dev Emergency function to cancel a transaction (only owner)
     * @param txId The transaction ID to cancel
     */
    function emergencyCancel(bytes32 txId) external onlyOwner {
        PendingTransaction storage txn = pendingTransactions[txId];
        require(!txn.executed, "Transaction already executed");
        require(txn.amount > 0, "Invalid transaction");
        
        txn.executed = true;
        userBalances[txn.user] += txn.amount;
    }
    
    /**
     * @dev Get contract balance information
     * @return totalBalance Total contract ETH balance
     * @return availableTax Available tax for withdrawal
     * @return userFunds Total user funds in the contract
     */
    function getContractInfo() external view returns (
        uint256 totalBalance,
        uint256 availableTax,
        uint256 userFunds
    ) {
        return (
            address(this).balance,
            totalCollectedTax,
            address(this).balance - totalCollectedTax
        );
    }
}
