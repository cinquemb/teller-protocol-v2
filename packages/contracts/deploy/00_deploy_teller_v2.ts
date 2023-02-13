import { ethers, getNamedSigner } from 'hardhat'
import { DeployFunction } from 'hardhat-deploy/dist/types'
import { HARDHAT_NETWORK_NAME } from 'hardhat/plugins'
import { deploy } from 'helpers/deploy-helpers'
import { isInitialized } from 'helpers/oz-contract-helpers'
import { CollateralManager, UpgradeableBeacon } from 'types/typechain'

import { getTokens } from '~~/config'

const deployFn: DeployFunction = async (hre) => {
  const protocolFee = 5 // 0.05%

  const marketRegistry = await hre.contracts.get('MarketRegistry')

  const tokens = await getTokens(hre)
  const lendingTokens = [tokens.all.DAI, tokens.all.USDC, tokens.all.WETH]
  if ('USDCT' in tokens.all) {
    lendingTokens.push(tokens.all.USDCT)
  }

  const trustedForwarder = await hre.contracts.get('MetaForwarder')

  console.log('about to deploy tellerV2 ', trustedForwarder.address)

  const tellerV2Contract = await deploy({
    contract: 'TellerV2',
    args: [trustedForwarder.address],
    mock: hre.network.name === HARDHAT_NETWORK_NAME,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
    skipIfAlreadyDeployed: false,
    hre,
  })

  /*  
     Need to initialize the LenderCommitmentForwarder after TellerV2 has been deployed because it is a MarketForwarder
  */
  const lenderCommitmentForwarder = await deploy({
    contract: 'LenderCommitmentForwarder',
    args: [tellerV2Contract.address, marketRegistry.address],
    skipIfAlreadyDeployed: true,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
    hre,
  })

  const reputationManager = await hre.contracts.get('ReputationManager')
  // Execute the initialize method of reputation manager
  const reputationIsInitialized = await isInitialized(reputationManager.address)
  if (!reputationIsInitialized) {
    console.log('initializing repuration manager')
    await reputationManager.initialize(tellerV2Contract.address)
  }

  const collateralEscrowBeaconImpl = await deploy({
    contract: 'CollateralEscrowV1',
    name: 'CollateralEscrow',
    skipIfAlreadyDeployed: true,
    hre,
  })

  const collateralEscrowBeacon = await deploy<UpgradeableBeacon>({
    contract: 'UpgradeableBeacon',
    name: 'CollateralEscrowBeacon',
    args: [collateralEscrowBeaconImpl.address],
    skipIfAlreadyDeployed: true,
    hre,
  })
  if (collateralEscrowBeaconImpl.deployResult.newlyDeployed) {
    hre.log(
      `Upgrading CollateralEscrow beacon to ${collateralEscrowBeaconImpl.address}... `,
      { indent: 2, star: true, nl: false }
    )
    await collateralEscrowBeacon.upgradeTo(collateralEscrowBeaconImpl.address)
    hre.log(`done`)
  }

  const collateralManager = await deploy<CollateralManager>({
    contract: 'CollateralManager',
    args: [],
    skipIfAlreadyDeployed: false,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [collateralEscrowBeacon.address, tellerV2Contract.address],
        },
      },
    },
    hre,
  })

  const tellerV2IsInitialized = await isInitialized(tellerV2Contract.address)
  if (!tellerV2IsInitialized) {
    console.log('initialize tellerV2')
    const lenderManager = await hre.contracts.get('LenderManager')
    await tellerV2Contract.initialize(
      protocolFee,
      marketRegistry.address,
      reputationManager.address,
      lenderCommitmentForwarder.address,
      lendingTokens,
      collateralManager.address,
      lenderManager.address
    )
  }

  let lenderManagerAddress

  try {
    lenderManagerAddress = await tellerV2Contract.lenderManager()
  } catch (e) {}

  if (
    !lenderManagerAddress ||
    lenderManagerAddress == ethers.constants.AddressZero
  ) {
    const lenderManager = await hre.contracts.get('LenderManager')

    console.log('running onUpgrade for tellerV2 ', lenderManager.address)

    await tellerV2Contract.onUpgrade(lenderManager.address)
  }
}

// tags and deployment
deployFn.tags = ['teller-v2']
deployFn.dependencies = [
  'meta-forwarder',
  'reputation-manager',
  'market-registry',
  'lender-manager',
]
export default deployFn
