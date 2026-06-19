use sha2::{Digest, Sha256};

pub fn sha256(data: &[u8]) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256_output_length() {
        let result = sha256(b"");
        assert_eq!(result.len(), 32);
    }

    #[test]
    fn test_sha256_hello() {
        let result = sha256(b"hello");
        assert_eq!(result.len(), 32);
        // Known SHA-256 of "hello"
        let expected: Vec<u8> = vec![
            0x2c, 0xf2, 0x4d, 0xba, 0x5f, 0xb0, 0xa3, 0x0e,
            0x26, 0xe8, 0x3b, 0x2a, 0xc5, 0xb9, 0xe2, 0x9e,
            0x1b, 0x16, 0x1e, 0x5c, 0x1f, 0xa7, 0x42, 0x5e,
            0x73, 0x04, 0x33, 0x62, 0x93, 0x8b, 0x98, 0x24,
        ];
        assert_eq!(result, expected);
    }

    #[test]
    fn test_sha256_deterministic() {
        let data = b"test data";
        assert_eq!(sha256(data), sha256(data));
    }

    #[test]
    fn test_sha256_different_inputs_different_outputs() {
        let a = sha256(b"apple");
        let b = sha256(b"banana");
        assert_ne!(a, b);
    }
}
