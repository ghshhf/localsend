use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, Serialize, PartialEq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DeviceType {
    Mobile,
    Desktop,
    Web,
    Headless,
    Server,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_type_serde_mobile() {
        let json = "\"MOBILE\"";
        let dt: DeviceType = serde_json::from_str(json).unwrap();
        assert!(matches!(dt, DeviceType::Mobile));
    }

    #[test]
    fn test_device_type_serde_desktop() {
        let json = "\"DESKTOP\"";
        let dt: DeviceType = serde_json::from_str(json).unwrap();
        assert!(matches!(dt, DeviceType::Desktop));
    }

    #[test]
    fn test_device_type_serde_roundtrip() {
        let dt = DeviceType::Mobile;
        let json = serde_json::to_string(&dt).unwrap();
        assert_eq!(json, "\"MOBILE\"");
        let back: DeviceType = serde_json::from_str(&json).unwrap();
        assert!(matches!(back, DeviceType::Mobile));
    }

    #[test]
    fn test_device_type_all_variants_serialize() {
        let variants = vec![
            DeviceType::Mobile,
            DeviceType::Desktop,
            DeviceType::Web,
            DeviceType::Headless,
            DeviceType::Server,
        ];
        for v in variants {
            let json = serde_json::to_string(&v).unwrap();
            let back: DeviceType = serde_json::from_str(&json).unwrap();
            assert_eq!(format!("{:?}", v), format!("{:?}", back));
        }
    }
}
