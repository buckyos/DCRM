const MyToken = artifacts.require("PSTToken");

contract("PSTToken", accounts => {
    const [initialHolder, recipient, anotherAccount] = accounts;

    beforeEach(async () => {
        this.myToken = await MyToken.new(1000);
    });

    it("should deploy with the initial supply", async () => {
        const supply = await this.myToken.totalSupply();
        assert.equal(supply.toNumber(), 1000, "Initial supply was not as expected");
    });

    it("initial holder should have the initial supply", async () => {
        const balance = await this.myToken.balanceOf(initialHolder);
        assert.equal(balance.toNumber(), 1000, "Initial holder does not have the initial supply");
    });

    it("should transfer tokens correctly", async () => {
        let amount = 100;
        await this.myToken.transfer(recipient, amount, { from: initialHolder });

        let initialHolderBalance = await this.myToken.balanceOf(initialHolder);
        assert.equal(initialHolderBalance.toNumber(), 900, "Amount wasn't correctly taken from the sender");

        let recipientBalance = await this.myToken.balanceOf(recipient);
        assert.equal(recipientBalance.toNumber(), 100, "Amount wasn't correctly sent to the receiver");
    });

    it("should not allow transferring more than balance", async () => {
        try {
            await this.myToken.transfer(recipient, 2000, { from: initialHolder });
            assert.fail("The transfer did not fail as expected");
        } catch (error) {
            assert(error, "Expected an error but did not get one");
            assert(error.message.includes("transfer amount exceeds balance"), "Expected 'transfer amount exceeds balance' error message");
        }
    });
});
