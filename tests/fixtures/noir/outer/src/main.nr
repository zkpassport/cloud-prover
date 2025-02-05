global SIZE_OF_PROOF_IF_LOGN_IS_28: u32 = 459;
global HONK_IDENTIFIER: u32 = 1;

fn main(
    vkey: [Field; 128],
    // This is the proof without public inputs attached.
    // This means: the size of this does not change with the number of public inputs.
    proof: [Field; SIZE_OF_PROOF_IF_LOGN_IS_28],
    public_inputs: pub [Field; 1],

) {
    std::verify_proof_with_type(
        vkey,
        proof,
        public_inputs,
        1,
        HONK_IDENTIFIER,
    );
    std::verify_proof_with_type(
        vkey,
        proof,
        public_inputs,
        2,
        HONK_IDENTIFIER,
    );
    std::verify_proof_with_type(
        vkey,
        proof,
        public_inputs,
        3,
        HONK_IDENTIFIER,
    );
    std::verify_proof_with_type(
        vkey,
        proof,
        public_inputs,
        4,
        HONK_IDENTIFIER,
    );
}
