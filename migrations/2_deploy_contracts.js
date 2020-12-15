const BRDToken = artifacts.require("BRDToken");

module.exports = function (deployer) {
  deployer.deploy(BRDToken);
};
