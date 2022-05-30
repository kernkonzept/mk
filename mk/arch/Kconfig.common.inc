# Common symbols for arm and arm64

config CPU_ARMV6PLUS
	bool
	default y if CPU_ARM_ARMV6 || CPU_ARM_ARMV6T2 || CPU_ARMV6KPLUS

config CPU_ARMV6KPLUS
	bool
	default y if CPU_ARM_ARMV6ZK || CPU_ARMV7PLUS

config CPU_ARMV7PLUS
	bool
	default y if CPU_ARM_ARMV7A || CPU_ARM_ARMV7R || CPU_ARMV8PLUS

config CPU_ARMV8PLUS
	bool
	default y if CPU_ARM_ARMV8R_AARCH32 || CPU_ARM_ARMV8R_AARCH64

