# ARCH:       BUILD_ARCH_riscv riscv
# ARCHDESCR:  RISC-V architecture
# ARCHSELECT: ARCH_ENABLE_STACK_PROTECTOR
# ARCHDEFAULTPF: PLATFORM_TYPE_riscv_virt

choice
	prompt "CPU variant"
	default CPU_RISCV_64IMA

config CPU_RISCV_32IMA
	bool "RV32IMA"

config CPU_RISCV_64IMA
	bool "RV64IMA"

endchoice

choice
	prompt "FPU"
	default FPU_RISCV_DOUBLE

config FPU_RISCV_NONE
	bool "Off"

config FPU_RISCV_SINGLE
	bool "Single precision"

config FPU_RISCV_DOUBLE
	bool "Double precision"

endchoice

config RISCV_ISA_C
	bool "Emit compressed instructions"
	default y

config CPU_RISCV_BITS
	string
	default "32" if CPU_RISCV_32IMA
	default "64" if CPU_RISCV_64IMA

config CPU
	string
	default "rv32ima" if CPU_RISCV_32IMA && FPU_RISCV_NONE && !RISCV_ISA_C
	default "rv32imaf" if CPU_RISCV_32IMA && FPU_RISCV_SINGLE && !RISCV_ISA_C
	default "rv32imafd" if CPU_RISCV_32IMA && FPU_RISCV_DOUBLE && !RISCV_ISA_C
	default "rv64ima" if CPU_RISCV_64IMA && FPU_RISCV_NONE && !RISCV_ISA_C
	default "rv64imaf" if CPU_RISCV_64IMA && FPU_RISCV_SINGLE && !RISCV_ISA_C
	default "rv64imafd" if CPU_RISCV_64IMA && FPU_RISCV_DOUBLE && !RISCV_ISA_C
	default "rv32imac" if CPU_RISCV_32IMA && FPU_RISCV_NONE && RISCV_ISA_C
	default "rv32imafc" if CPU_RISCV_32IMA && FPU_RISCV_SINGLE && RISCV_ISA_C
	default "rv32imafdc" if CPU_RISCV_32IMA && FPU_RISCV_DOUBLE && RISCV_ISA_C
	default "rv64imac" if CPU_RISCV_64IMA && FPU_RISCV_NONE && RISCV_ISA_C
	default "rv64imafc" if CPU_RISCV_64IMA && FPU_RISCV_SINGLE && RISCV_ISA_C
	default "rv64imafdc" if CPU_RISCV_64IMA && FPU_RISCV_DOUBLE && RISCV_ISA_C

config CPU_ABI
	string
	default "ilp32" if CPU_RISCV_32IMA && FPU_RISCV_NONE
	default "ilp32f" if CPU_RISCV_32IMA && FPU_RISCV_SINGLE
	default "ilp32d" if CPU_RISCV_32IMA && FPU_RISCV_DOUBLE
	default "lp64" if CPU_RISCV_64IMA && FPU_RISCV_NONE
	default "lp64f" if CPU_RISCV_64IMA && FPU_RISCV_SINGLE
	default "lp64d" if CPU_RISCV_64IMA && FPU_RISCV_DOUBLE
