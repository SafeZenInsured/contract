module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log, save } = deployments
    const { deployer } = await getNamedAccounts()

    const DAI_TOKEN_CONTRACT = await ethers.getContract("MockDAI")
    const DAI_TOKEN_ADDRESS = DAI_TOKEN_CONTRACT.address

    const SZTDAI_TOKEN_CONTRACT = await ethers.getContract("sztDAI")
    const SZTDAI_TOKEN_ADDRESS = SZTDAI_TOKEN_CONTRACT.address

    const SWAPDAI_CONTRACT = await ethers.getContractFactory("SwapDAI");
    const SWAPDAI = await upgrades.deployProxy(
        SWAPDAI_CONTRACT, 
        [], 
        {
            constructorArgs: [DAI_TOKEN_ADDRESS, SZTDAI_TOKEN_ADDRESS], 
            unsafeAllow: ['constructor', 'state-variable-immutable'],
        }
    );

    await SWAPDAI.deployed();
    console.log("Swap DAI Contract Proxy deployed at:", SWAPDAI.address);

    const artifact = await deployments.getExtendedArtifact('SwapDAI');
    let proxyDeployments = {
        address: SWAPDAI.address,
        ...artifact
    }
    await save('SwapDAI', proxyDeployments);
    console.log(`Swap DAI Contract has been deployed on ${SWAPDAI.address} address.`)
}

module.exports.tags = ["all", "SwapDAI"]