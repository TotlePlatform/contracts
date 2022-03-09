var PartnerRegistry = artifacts.require("PartnerRegistry");
var Partner = artifacts.require("Partner");

contract('PartnerRegistry', (accounts) => {
    var partnerRegistry,
        partnerTarget
    beforeEach(async () => {
        partnerTarget = await Partner.new()
        partnerRegistry = await PartnerRegistry.new("0x0000000000000000000000000000000000000000", partnerTarget.address, "0xEC3281124d4c2FCA8A88e3076C1E7749CfEcb7F2", "10000000000000000")
    })

    it("shouldn't allow non-owner to create overridden partners", async () => {
        try {
            await partnerRegistry.overrideRegisterPartner("0x0000000000000000000000000000000000000002", "1000", "0x0000000000000000000000000000000000000002", "1000", { from: accounts[1] })
        } catch (e) {
            return;
        }
        assert.fail("Should've reverted")
    });

    it("should allow owner to create partners", async () => {
        try {
            await partnerRegistry.registerPartner("0x0000000000000000000000000000000000000002", "1000")
        } catch (e) {
            assert.fail("shouldn't have reverted")
        }
    });
});
