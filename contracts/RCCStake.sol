// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";


contract RCCStake is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    //*************************** INVARIANTS ***************************
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    uint256 public constant nativeCurrency_PID = 0;

    //*************************** DATA STRUCTURE ***************************
    struct Pool {
        //质押代币的地址
        address stTokenAdress;
        //质押池的权重，影响奖励分配
        uint256 poolWeight;
        //最后一次计算奖励的区块号
        uint256 lastRewordBlock;
        //每个质押代币累积的 RCC 数量
        uint256 accRCCPerST;
        //池中的总质押代币量
        uint256 stTokenAmount;
        //最小质押数量
        uint256 minDepositAmount;
        //解除质押的锁定区块数
        uint256 unstakeLockedBlocks;
    }

    struct UnstakeRequest {
        //解质押数量
        uint256 amount;
        //解锁区块
        uint256 unlockBlocks;
    }

    struct User {
        //用户质押的代币数量
        uint256 stAmount;
        //已分配的 RCC 数量
        uint256 finishedRCC;
        //待领取的 RCC 数量
        uint256 pendingRCC;
        //解质押请求列表，每个请求包含解质押数量和解锁区块
        UnstakeRequest[] requests;
    }

    //**********************************************STAT VARIABLES ***************************
    //质押开始的区块号
    uint256 public startBlock;
    //质押结束的区块号
    uint256 public endBlock;
    //每个区块的奖励
    uint256 public RCCPerBlock;

    //暂停提币
    bool public withdrawPaused;
    //暂停索赔
    bool public claimPaused;

    //RCC token
    IERC20 public RCC;

    //质押池总权重
    uint256 public totalPoolWeight;
    //质押池
    Pool[] public pool;
    //质押用户信息  poolId => （user address => user)
    mapping(uint256 => mapping(address => User)) public user;

    //********************************************** EVENT ***************************
    //设置奖励token合约
    event SetRcc(IERC20 indexed RCC);

    //暂停提币
    event PauseWithdraw();
    //恢复提币
    event UnPauseWithdraw();

    //暂停索赔
    event PauseClaim();
    //恢复索赔
    event UnPauseClaim();

    //设置起始块号
    event SetStartBlock(uint256 indexed startBlock);

    //设置结束块号
    event SetEndBlock(uint256 indexed endBlock);

    //设置每个块奖励的RCC数量
    event SetRCCPerBlock(uint256 indexed RCCPerBlock);

    //添加质押池
    event AddPool(
        address indexed stTokenAddress,
        uint256 indexed poolWeight,
        uint256 indexed lastRewardBlock,
        uint256 minDepositAmount,
        uint256 unstatkeLockedBlock
    );

    //更新质押池 最小质押数、解除质押的锁定区块数
    event UpdatePoolInfo(
        uint256 indexed poolId,
        uint256 indexed minDepositAmount,
        uint256 indexed unstatkeLockedBlock
    );

    //设置质押池
    event SetPoolWight(
        uint256 indexed poolId,
        address indexed poolWeight,
        uint256 indexed totalPoolWeight
    );

    //更新质押池
    event UpdatePool(
        uint256 indexed poolId,
        uint256 indexed lastRewordBlock,
        uint256 totalRCC
    );

    //抵押
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);

    //解除质押
    event RequestUnStake(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    //提币
    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 indexed blockNumber
    );

    //索赔
    event Claim(address indexed user, uint256 indexed poolId, uint256 RCCRward);

    //********************************************** MODIFIER ***************************
    //质押池id有效性判断
    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "invalid pid");
        _;
    }

    //索赔开启
    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }

    //提现开启
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    
    function initialize(
        IERC20 _RCC,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _RCCPerBlock
    ) public initializer{
        
        require(_startBlock < _endBlock && _RCCPerBlock > 0 ,"invalid params");
        //初始化访问控制
        __AccessControl_init();
        //初始化可升级方法
        __UUPSUpgradeable_init();
        //授权
        _grantRole(DEFAULT_ADMIN_ROLE,msg.sender);
        _grantRole(UPGRADE_ROLE,msg.sender);
        _grantRole(ADMIN_ROLE,msg.sender);
        //设置代币
        setRCC(_RCC);

        startBlock = _startBlock;
        endBlock = _endBlock;
        RCCPerBlock = _RCCPerBlock;
    }


    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADE_ROLE) override{

    }


    //********************************************** ADMIN FUNCTION ***************************
    /**
     *   设置RCC token 地址
     */
    function setRCC(IERC20 _RCC) public onlyRole(ADMIN_ROLE) {
        RCC = _RCC;
        emit SetRcc(_RCC);
    }


    function pauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(!withdrawPaused ,"withdraw has been already paused");

        withdrawPaused = true;
        emit PauseWithdraw();
    }

    function unPauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(withdrawPaused ,"withdraw has been already unpaused");

        withdrawPaused = false;
        emit UnPauseWithdraw();
    }

    function pauseClaim() public onlyRole(ADMIN_ROLE){
        require(!claimPaused,"claim has been already paused");
        claimPaused = true;
        emit PauseClaim();
    }

    function unPauseClaim() public onlyRole(ADMIN_ROLE){
        require(claimPaused,"claim has been already unpaused");
        claimPaused = false;
        emit UnPauseClaim();
    }

    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE){
        require(_startBlock <= endBlock,"start block must be smaller than end block");
        startBlock = _startBlock;
        emit SetStartBlock(_startBlock);

    }

    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE){
        require(startBlock <= _endBlock,"end block must be bigger than end block");
        endBlock = _endBlock;
        emit SetEndBlock(_endBlock);

    }

    function setRCCPerBlock(uint256 _RCCPerBlock) public onlyRole(ADMIN_ROLE){
        require(_RCCPerBlock>0,"invalid parameter");
        RCCPerBlock = _RCCPerBlock;
        emit SetRCCPerBlock(_RCCPerBlock);
    }


    



}
