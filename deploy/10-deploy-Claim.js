module.exports = async ({ deployments, getChainId }) => {
    const { save } = deployments
    
    const GSZT_CONTRACT = await ethers.getContract("GSZT")
    const GSZT_ADDRESS = GSZT_CONTRACT.address

    const GLOBAL_PAUSE_CONTRACT = await ethers.getContract("GlobalPauseOperation")
    const GLOBAL_PAUSE_ADDRESS = GLOBAL_PAUSE_CONTRACT.address

    const CLAIM_GOVERNANCE_CONTRACT = await ethers.getContractFactory("ClaimGovernance");
    const CLAIM_GOVERNANCE_REGISTRY = await upgrades.deployProxy(
        CLAIM_GOVERNANCE_CONTRACT, 
        [GSZT_ADDRESS, GLOBAL_PAUSE_ADDRESS], 
        {}
    );
    await CLAIM_GOVERNANCE_REGISTRY.deployed();
    console.log("Claim Contract Proxy deployed at:", CLAIM_GOVERNANCE_REGISTRY.address);

    const artifact = await deployments.getExtendedArtifact('ClaimGovernance');
    let proxyDeployments = {
        address: CLAIM_GOVERNANCE_REGISTRY.address,
        ...artifact
    }
    await save('ClaimGovernance', proxyDeployments);
    console.log(`Claim Contract has been deployed on ${CLAIM_GOVERNANCE_REGISTRY.address} address.`)

}

module.exports.tags = ["all", "ClaimGovernance"]