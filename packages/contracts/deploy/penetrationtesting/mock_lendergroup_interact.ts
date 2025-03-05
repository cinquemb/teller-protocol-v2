import { DeployFunction } from 'hardhat-deploy/dist/types'
import { deploy } from 'helpers/deploy-helpers'


const deployFn: DeployFunction = async (hre) => {

  

  const lenderGroupMockInteract = await  deploy({
    contract: 'LenderGroupMockInteract',
    //args: [ ] ,
    skipIfAlreadyDeployed: true,
    hre,
  })

  return true
}

// tags and deployment
deployFn.id = 'lendergroup-mock-interact:deploy'
deployFn.tags = ['hypernative-oracle-mock:deploy']
deployFn.dependencies = []
deployFn.skip = async (hre) => {
    return !hre.network.live || ![  'polygon'].includes(hre.network.name)
  }
export default deployFn
