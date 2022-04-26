module.exports = {
    providerOptions: {
        network_id: 6777,
    },
    mocha: {
        grep: "@skip-on-coverage", // Find everything with this tag
        invert: true, // Run the grep's inverse set.
        enableTimeouts: false
    },
    configureYulOptimizer: true
};