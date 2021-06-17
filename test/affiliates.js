var AffiliateRegistry = artifacts.require("AffiliateRegistry");
var Affiliate = artifacts.require("Affiliate");

contract('AffiliateRegistry', (accounts) => {
    var affiliateRegistry,
        affiliateTarget
    beforeEach(async () => {
        affiliateTarget = await Affiliate.new()
        await affiliateTarget.init("0x0000000000000000000000000000000000000001", "1000", "0x0000000000000000000000000000000000000001", "1000")
        affiliateRegistry = await AffiliateRegistry.new(affiliateTarget.address, "0xEC3281124d4c2FCA8A88e3076C1E7749CfEcb7F2", "1000")
    })

    it("shouldn't allow non-owner to create overridden affiliates", async () => {
        try {
            await affiliateRegistry.overrideRegisterAffiliate("0x0000000000000000000000000000000000000002", "1000", "0x0000000000000000000000000000000000000002", "1000", {from: accounts[1]})
        } catch (e) {
            return;
        }
        assert.fail("Should've reverted")
    });

    it("should allow owner to create affiliates", async () => {
        try {
            await affiliateRegistry.registerAffiliate("0x0000000000000000000000000000000000000002", "1000")
        } catch (e) {
            assert.fail("shouldn't have reverted")
        }
    });
});
