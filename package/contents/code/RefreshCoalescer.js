// Coalesce the usage refresh a successful pricing refresh triggers.
//
// Refreshing the pricing catalog only changes derived *cost* values, so a
// failed pricing refresh must cause no usage work at all. A successful one
// needs exactly one usage refresh — but the user can also press pricing while
// a scheduled usage refresh is already in flight. Launching a second one then
// would cancel and re-run the first (two backend calls, one visible update).
//
// This policy makes that at most one additional refresh: while a usage request
// is in flight a completed pricing refresh just marks one pending, which fires
// when the in-flight request settles.

function nextAction(pricingOk, usageInFlight, usagePending) {
    // A failed (or absent) pricing refresh leaves derived values unchanged.
    if (pricingOk !== true)
        return "none";
    if (usageInFlight === true)
        return usagePending === true ? "none" : "mark-pending";
    return "refresh-now";
}

// Pricing status is independent of usage state: a pricing-only update must
// never blank the usage view. Exposed so a frontend can assert it does not
// clear usage on a pricing transition.
function blanksUsage(_previousStatus, _nextStatus) {
    return false;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        nextAction: nextAction,
        blanksUsage: blanksUsage
    };
}
