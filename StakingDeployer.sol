pragma solidity 0.6.12;

import './Deployer.sol';
import './Staking.sol';
import './interfaces/IERC20.sol';

/* It's neccessary because GasLimit on Moonriver Network */

contract StakingDeployer{
    Deployer private deployer;
    
    constructor (address _deployer) public {
        deployer = Deployer( payable(_deployer) );
        Staking LPStaking = new Staking(
            deployer.lpToken(),
            deployer.REWARD_PER_BLOCK(),
            ( (deployer.VALID_TILL() - deployer.START_TIME()) / 13 ) + deployer.stakingBlocksOffset() // start 4 hours after pre-sale
        );
        
        Staking NativeStaking = new Staking(
            deployer.beamToken(),
            deployer.REWARD_PER_BLOCK(),
            ( (deployer.VALID_TILL() - deployer.START_TIME()) / 13 ) + deployer.stakingBlocksOffset()
        );
        
        LPStaking.add( deployer.LP_STAKING_TOKENS(), deployer.lpToken(), false);
        NativeStaking.add( deployer.NATIVE_STAKING_TOKENS(), deployer.beamToken(), false);
        
        deployer.setLPStaking(LPStaking); 
        deployer.setNativeStaking(NativeStaking);
    }
}