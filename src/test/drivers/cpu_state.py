from enum import Enum, auto


class CPUOp(Enum):
    NOP = auto()
    READ_DATA = auto()
    
    # Interleaved
    READ_FIFO = auto()
    READ_AGU_DONE_PTR = auto()
    WRITE_CPU_DONE_PTR = auto()
        
    # Blockwise
    READ_NUM_BLOCKS = auto()
    READ_BLOCK_ID = auto()
    READ_BLOCK_SIZE = auto()
    WRITE_RELEASE_BANK = auto()
    