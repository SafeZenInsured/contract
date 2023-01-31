/// Contract not initialized after deploying.

const VALUE = 1
const DECIMALS = 4

module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    const chainID = await getChainId()
    
    if (chainID != 31337) {
        const DAI_CONTRACT = await ethers.getContract("MockDAI");
        const DAI_ADDRESS = DAI_CONTRACT.address

        const BUYSELLSZT_CONTRACT = await ethers.getContractFactory("BuySellSZT");
        const BUYSELLSZT = await upgrades.deployProxy(BUYSELLSZT_CONTRACT, [], {
            constructorArgs: [VALUE, DECIMALS, DAI_ADDRESS], 
            unsafeAllow: ['constructor', 'state-variable-immutable'],
            initializer: "initialize",
        });
        await BUYSELLSZT.deployed();
        console.log("BuySellSZT Proxy deployed at:", BUYSELLSZT.address);

        const artifact = await deployments.getExtendedArtifact('BuySellSZT');
        let proxyDeployments = {
            address: BUYSELLSZT.address,
            ...artifact
        }

        await save('BuySellSZT', proxyDeployments);
        console.log(`BuySellSZT Contract has been deployed on ${BUYSELLSZT.address} address.`)

    } else {
        DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
        LUSD_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F"

        const BUYSELLSZT_CONTRACT = await ethers.getContractFactory("BuySellSZT");
        const BUYSELLSZT = await upgrades.deployProxy(BUYSELLSZT_CONTRACT, [], {
            constructorArgs: [VALUE, DECIMALS, DAI_ADDRESS, LUSD_ADDRESS], 
            unsafeAllow: ['constructor', 'state-variable-immutable'],
            // initializer: initialize,
        });
        await BUYSELLSZT.deployed();
        console.log("Proxy deployed at:", BUYSELLSZT.address);

        const artifact = await deployments.getExtendedArtifact('BuySellSZT');
        let proxyDeployments = {
            address: BUYSELLSZT.address,
            ...artifact
        }

        await save('BuySellSZT', proxyDeployments);
        console.log(`Buy Sell SZT Contract has been deployed on ${BUYSELLSZT.address} address.`)
        
        
        
    }

    
}

module.exports.tags = ["all", "BuySellSZT"]