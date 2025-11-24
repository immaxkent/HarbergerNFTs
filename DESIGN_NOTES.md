# Design Notes

The following is a collection of notes specifying design and decisions made through implementation, as well as footnotes which comprise of running thoughts arising throughout implementation.

## Security Considerations

- Reentrancy guards have been placed on critical functions, whereby extrernal calls are made
- Underflow/overflow is handled by solidity versions (0.8.13+)
- Critical errros in rounding may have arisen from the tax formula, which handles this with a scaling factor of 1e18
- Edge cases, for high/low inputs of price (the only user-input critical value) have been addressed with MAX_PRICE and MIN_PRICE and surrounding tests

## Tax Model

A Harberger NFT is a token that is subject to a tax rate levied proportionally to value of the NFT. In this design, tax is paid in Ether. Some notes on design decisions:

- We can apply some rate X to yield an annual tax rate X% for owning an asset. This is defined as `GLOBAL_TAX_RATE` in the contract, initialised at constructor.
- Taxes MUST be paid via contract and are assigned to the tax recipient, denoted `treasury`.
- We use the tax equation `(price * taxRate * secondsElapsed) / (365 days * 10_000)` to calculate tax due, where `taxRate` is `GLOBAL_TAX_RATE` and `secondsElapsed` is the time elapsed since the last modification of the NFT.

## Foreclosure

- We put an evaluative cliff in place modifyable via setters, for the payment of taxes and ensure we have covered twice block time past that cliff to check for tax payments/modifications. If unpaid, the asset is confiscated and 'sold' (transferred) to the treasury via a dedicated call, the function `evaluateAndAddress()`.

## Footnotes & Running Thoughts wrt Original Spec

The following are design notes made through implementation of the codebase.

1. We use mappings to store metadatas as they present a more gas efficient way to cover storage layouts and access than, say, dedicated structs, specifically where structs (or at least, chunks of data) are NOT being passed function to function or contreact to contract.
2. Modification of the NFT requires immediate payment of outstanding tax in this design. There are a number of options here, but would lie in the field of 'product' more than 'engineering'. As such, if this contract/architecture were to move to production this factor may be given more scrutiny (e.g. compound the interest accrued with the new interest rate post timestamp `t`, or whatever). The 'shape' of this element in this design has been elected for simplicity.
3. Consideration was given to adding a per NFT tax rate, for customisability during mint, but felt it just added more complexity without a large increase in design elegance. The angle taken here was 'those minting Harberger NFTs would be incentivised to write as near-zerro tax rate as possible since that levy falls on their head', and as such this was left to governance.
4. Tokens minted are given value and charged tax in units of Ether. This is a design choice and may be changed in the future similarly to other architecture design aspects.
5. This design sees defaulted NFTs are unable to be purchased back from the treasury. Again, this is a design choice and is liable to design change if taken to production.
6. Purchasing does not allow re-definition of the price/value of the NFT in the same call. This should be done in a subsequent call to `modify`.
7. Two functions exist for analysing tax: one returns _tax due_, whilst the other _evaluates tax status_ AND provides for _defaulting_ (where NFTs are repossessed by the treasury). The latter serves as an endpoint for automatic tax evaluation (on owner call) and/or maintainer driven tax analysis.
8. The `evaluate()` function may be called by some sort of protocol maintainer, e.g. a server side repo run via cron job on github or similar OR an EOA OR the owner .... or whatever. Again, this aspect is left to iteration if taken to production, but noted ehre for conciceness and brevity in design analysis.
9. Extends OpenZeppelin's ERC721 contract.
10. Seems harsh to confiscate an NFT someone may have paid a high value for, but has been left in the design
11. Setting new `Cliff` and/or new `GLOBAL_TAX_RATE` doesn't retroactively charge or update existing NFTs.
12. The system DOES allow some NFTs to go over their default AND THEN be paid. Only calls to `evaluateAndAddress()` will result in a default.
13. Users are able to interact with NFTs that SHOULD be defaulted, but are not. Its a subsequence of design, and we rely solely on evaluateAndAddress as the endpoint for defaulting on outstanding payments
