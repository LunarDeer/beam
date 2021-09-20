pragma solidity ^0.6.0;

import "./interfaces/ISwap.sol";
import "./interfaces/IFactory.sol";

import "./utils/Context.sol";
import "./utils/Ownable.sol";
import "./utils/SafeMath.sol";
import "./utils/Address.sol";

import "./Token.sol";
import "./Staking.sol";

contract Deployer is Context, Ownable {
    /* LIBS */
    using Address for address;
    using SafeMath for uint256;
    
    /* TOKEN */
    Beam public beamToken;
    uint256 internal _tokenDecimals = 9;
    uint256 internal totalRewards = 0;
    
    /* STAKING */
    Staking public LPStaking;
    Staking public NativeStaking;
    uint256 public REWARD_PER_BLOCK;
    
    /* PRESALE CONFIG */    
    uint256 internal constant SOFT_CAP = 250 * 10**18;
    uint256 internal constant HARD_CAP = 600 * 10**18;
    
    uint256 private TOTAL_TOKENS = 10 * 10**9 * 10**_tokenDecimals;
    
    uint256 internal FARM_TOKENS = TOTAL_TOKENS.div(100).mul(75);
        uint256 public NATIVE_STAKING_TOKENS = FARM_TOKENS.div(100).mul(30);
        uint256 public LP_STAKING_TOKENS = FARM_TOKENS.div(100).mul(70);
    uint256 internal TEAM_TOKENS = TOTAL_TOKENS.div(100).mul(5);
    uint256 internal PRESALE_TOKENS = TOTAL_TOKENS.sub(FARM_TOKENS).sub(TEAM_TOKENS);
        uint256 internal TOKENS_TO_LIQIDITY = PRESALE_TOKENS.div(2);
        uint256 public PRESALE_RATIO = ((PRESALE_TOKENS.sub(TOKENS_TO_LIQIDITY)).div(10**_tokenDecimals)).div(HARD_CAP.div(10**18));
        uint256 internal INSTANT_LIMIT = 10 * 10**18;
    
    uint256 public START_TIME;
    uint256 public VALID_TILL;
    uint256 public stakingBlocksOffset = 1108; // 60 * 60 * 4 / 13
    
    /* SERVICE */
    address[] public participants;
    uint256 public totalRiver;
    mapping(address => uint) public liquidityShare;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public rewards;
    
    /* DEX */
    address internal FACTORY_ADDRESS = 0x049581aEB6Fe262727f290165C29BDAB065a1B68 ;
    address internal ROUTER_ADDRESS = 0xAA30eF758139ae4a7f798112902Bf6d65612045f ;
    IFactory internal factory;
    ISwap internal router;
    
    address internal LP_TOKEN_ADDRESS;
    IERC20 public lpToken;
    
    uint256 internal additionalBalanceAmount;
    uint256 internal additionalRewardAmount;
    uint256 internal additionalRewardRedeemed;
    
    constructor(
        uint256 _startTime, 
        uint256 _presaleDays) public payable {
            require(msg.value > 0, "constructor:: no balance for genesis liqidity");
            beamToken = new Beam(address(this), ROUTER_ADDRESS);
            factory = IFactory(FACTORY_ADDRESS);
            router = ISwap(ROUTER_ADDRESS);

            START_TIME = _startTime;
            VALID_TILL = _startTime + 60*3;//(_presaleDays * 1 days);
            beamToken.approve(address(this), ~uint256(0));
            require(beamToken.approve(ROUTER_ADDRESS, ~uint256(0)), "Approve failed");
            REWARD_PER_BLOCK = FARM_TOKENS / 425352;
            
            /* CREATING GENESIS LIQIDITY */ 
            uint256 tokenAmount = _rewardFromRiver(msg.value);
            router.addLiquidityETH{ value: msg.value }( 
                address(beamToken), //token
                tokenAmount, // amountTokenDesired
                0, // amountTokenMin
                msg.value, // amountETHMin
                address(0), 
                block.timestamp + 120 // deadline
            );
            totalRewards = totalRewards.add( tokenAmount );
            totalRiver = totalRiver.add( msg.value );
            LP_TOKEN_ADDRESS = factory.getPair( router.WETH(), address(beamToken) );
            lpToken = IERC20( LP_TOKEN_ADDRESS );
            require( lpToken.approve( ROUTER_ADDRESS, ~uint256(0)) );
            beamToken.setLPPair( LP_TOKEN_ADDRESS );
    }   


    function setLPStaking(Staking _Staking) public {
        require(tx.origin == owner());
        LPStaking = _Staking;
    }
    
    function setNativeStaking(Staking _Staking) public {
        require(tx.origin == owner());
        NativeStaking = _Staking;
    }

    function _startTime() public view returns (uint256) {
        return START_TIME;
    }
    
    function _endTime() public view returns (uint256) {
        return VALID_TILL;
    }
    
    function _participantsLength() public view returns (uint256) {
        return participants.length;
    }
    
    function _totalRewards() public view returns (uint256) {
        return totalRewards;
    }
    
    function adjustStart(uint256 timestamp) public onlyOwner() {
        START_TIME = timestamp;
    }
    
    function adjustEnd(uint256 timestamp) public onlyOwner() {
        VALID_TILL = timestamp;
    }
    
    function _rewardFromRiver(uint256 _value) internal view returns (uint256 reward) {
        return _value.mul(PRESALE_RATIO).mul(10**_tokenDecimals).div(10**18); 
    }
    
    function _riverFromReward(uint256 _value) internal view returns (uint256 _wei) {
        return _value.div(PRESALE_RATIO).mul(10**18).div(10**_tokenDecimals); 
    }

    function addLiquidity(address sender, uint256 tokenAmount, uint256 riverAmount) internal {
        (,,uint liqidity) = router.addLiquidityETH{ value: riverAmount }( 
                address(beamToken), //token
                tokenAmount, // amountTokenDesired
                0, // amountTokenMin
                riverAmount, // amountETHMin
                address(this), 
                block.timestamp + 120 // deadline
            );
        require(liqidity > 0, "addLiquidity:: zero-liqidity");
        liquidityShare[sender] = liquidityShare[sender].add(liqidity);
        totalRewards = totalRewards.add( tokenAmount );
        beamToken.transferNoFee( address(this), sender, tokenAmount );
    }
    
    function removeLiquidity(address sender) internal returns(uint256 tokenAmount, uint256 riverAmount) {
        (uint256 _tokenAmount, uint256 _riverAmount) = router.removeLiquidityETH(
                address(beamToken),
                liquidityShare[sender],
                0,
                0,
                address(this),
                block.timestamp + 120
            );
        liquidityShare[sender] = 0;    
        return (_tokenAmount, _riverAmount);
    }
    
    function _getTokenAmountFromShare(
        uint256 _balance, 
        address participant, 
        uint256 tokenAmountTotal
        ) internal view returns (uint256 _tokenAmount) {
        uint256 balance = balances[participant];
        if(balance > 0){ 
            uint256 balanceShare = (balance.div( _balance.div(100) )).div(100);
            uint256 tokenAmount = tokenAmountTotal.mul(balanceShare);
            return tokenAmount;
        } else {
            return 0;
        }
        
    }
    
    function refundAll(uint256 offsetLower, uint256 offsetUpper) public onlyOwner() {
        require( block.timestamp > VALID_TILL, "Presale is not over yet" );
        if(totalRiver < SOFT_CAP) {
            for(uint256 i = offsetLower; i <= offsetUpper; i++){
                if ( participants[i] == address(0) ) { // skip purged elements of queue
                    continue;
                } else if ( balances[participants[i]] > 0 ) {
                    address participant = participants[i];
                    (,uint256 RiverFromLP) = removeLiquidity(participant);
                    uint256 _balance = balances[participant].add( RiverFromLP );
                    balances[participants[i]] = 0;
                    payable(participant).transfer( _balance );
                        
                }
            }
        }
    }
    
    function endPresale() public returns (bool) {
        require( block.timestamp > VALID_TILL, "Presale is not over yet" );
        require( totalRiver >= SOFT_CAP, "Soft cap didnt reached");

        if(address(this).balance > 0) {
            uint256 _balance = address(this).balance;
            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = address(beamToken);
            uint[] memory amounts = router.swapExactETHForTokens{value: _balance}(
                0,
                path,
                address(this),
                block.timestamp + 120
            );
            
            additionalBalanceAmount = _balance;
            additionalRewardAmount = amounts[ amounts.length - 1 ];
        
        }
        
        /* INIT STAKINGS */
        uint256 _stakingStart = block.number + stakingBlocksOffset;

        beamToken.transferNoFee( address(this), address(LPStaking), LP_STAKING_TOKENS );
        LPStaking.fund(LP_STAKING_TOKENS);
        LPStaking.setStartBlock(_stakingStart);

        beamToken.transferNoFee( address(this), address(NativeStaking), NATIVE_STAKING_TOKENS );
        NativeStaking.fund(NATIVE_STAKING_TOKENS);
        NativeStaking.setStartBlock(_stakingStart);
        
        
        beamToken.approve( address(NativeStaking), ~uint256(0) );                
        beamToken.approve( address(LPStaking), ~uint256(0) );                
        /*                   */
        
        require(beamToken.transferNoFee(address(this), owner(), TEAM_TOKENS), "Team tokens transfer failed");
        require(beamToken.unlockAfterPresale(), "Token is not unlocked");

        return true;
    }

    function claimReward() public {
        address participant = _msgSender();
        uint256 _share = _getTokenAmountFromShare(additionalBalanceAmount, participant, additionalRewardAmount);
        require(_share > 0, "Nothing to claim");
        additionalRewardRedeemed = additionalRewardRedeemed.add(_share);
        beamToken.transferFrom( address(this), participant, _share );    
    }
    
    function burnRemainingTokens() public onlyOwner() {
        require(additionalRewardRedeemed >= additionalRewardAmount, "Cannot burn");
        beamToken.transferNoFee( address(this), address(0), beamToken.balanceOf(address(this)));
    }

    function withdraw() public { // Participans can withdraw their balance at anytime during the pre-sale
        require(
            (block.timestamp < VALID_TILL) ||
            (block.timestamp > VALID_TILL + 2 days), "Cannot withdraw");
        address payable sender = payable(_msgSender());
        uint256 _balance = balances[sender];
        uint256 _reward = rewards[sender];
        
        require(address(this).balance > 0 || liquidityShare[sender] > 0, "Nothing to withdraw");
        require(_balance > 0 || rewards[sender] > 0, "Cannot withdraw zero balance");
        
        balances[sender] = 0;
        rewards[sender] = 0;

        if( liquidityShare[sender] > 0 ){
            removeLiquidity(sender);
        }
        
        uint256 _totalUserToken = _reward;
        uint256 _river = _riverFromReward(_totalUserToken);
        uint256 _totalUserRiver = _balance.add(_river);
        
        totalRiver = totalRiver.sub(_totalUserRiver);
        totalRewards = totalRewards.sub(_totalUserToken);
        
        beamToken.transferNoFee(sender, address(this), _totalUserToken);
        sender.transfer(_totalUserRiver);
    }
     
    receive () external payable {
        require(msg.value > 0, 'receive:: Cannot deposit zero MOVR');
        address sender = _msgSender();
        if(!sender.isContract()) {
            uint256 _time = block.timestamp;
            require(_time >= START_TIME, "Presale does not started");
            require(_time <= VALID_TILL, "Presale is over");
            if(balances[sender] == 0 && rewards[sender] == 0) {
                participants.push(sender);
            }
            
            uint256 instantValue;
            uint256 delayedValue;
            
            uint256 _reward = _rewardFromRiver(msg.value);
            uint256 _preTotalRewards = totalRewards.add( _reward );
    
            if( _preTotalRewards <= TOKENS_TO_LIQIDITY ) {
                if (msg.value <= INSTANT_LIMIT) {
                    instantValue = msg.value;
                    delayedValue = 0;
                } else {
                    delayedValue = msg.value.sub(INSTANT_LIMIT);
                    instantValue = msg.value.sub(delayedValue);
                }
                
                if (instantValue > 0){    
                    uint256 reward = _rewardFromRiver(instantValue);
                    rewards[sender] = rewards[sender].add( reward );
                    addLiquidity(sender, reward, instantValue);
                }
                
                if (delayedValue > 0){
                    balances[sender] = balances[sender].add( delayedValue );
                }
                totalRiver = totalRiver.add( msg.value );
            } else {
                uint256 overflow = _preTotalRewards.sub( TOKENS_TO_LIQIDITY , "Receive:: underflow");
                uint256 instantTokenValue = _reward.sub( overflow );
                if ( instantTokenValue > 0 ){
                    rewards[sender] = rewards[sender].add( instantTokenValue );
                    instantValue = _riverFromReward(instantTokenValue);
                    addLiquidity(sender, instantTokenValue, instantValue);
                }
                uint256 _river =  _riverFromReward(overflow);
                totalRiver = totalRiver.add( _river ).add(instantValue);
                balances[sender] = balances[sender].add( _river );
            }
        }
    }
}