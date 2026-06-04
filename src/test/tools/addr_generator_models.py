from enum import IntEnum

class Mode(IntEnum):
    LINEAR = 0
    STRIDED = 1


class LinearGeneratorModel:
    def __init__(self):
        self.current_addr = 0
        
    def initialize(self, config_payload=None, base_addr=0):
        self.current_addr = base_addr
        
    def step(self):
        out_addr = self.current_addr
        self.current_addr += 1
        return out_addr
        

class StridedGeneratorModel:
    def __init__(self, count_width, stride_width, num_axes):        
        self.count_width = count_width
        self.stride_width = stride_width
        self.num_axes = num_axes 
        
        self.base_addr = 0
        self.current_addr = 0
        self.strides = []
        self.counts = []
        self.counters = []
        
    def initialize(self, config_payload, base_addr=0):        
        self.base_addr = base_addr
        self.current_addr = base_addr
        
        strides, counts = self.unpack_config_payload(config_payload)
        self.strides = strides
        self.counts = counts
        self.counters = [0 for _ in range(self.num_axes)]
    
    def step(self):
        out_addr = self.current_addr
        
        for i in range(self.num_axes):
            self.counters[i] += 1
            
            if self.counters[i] < self.counts[i]:
                break
            else:
                self.counters[i] = 0
    
        next_addr = self.base_addr
        for i in range(self.num_axes):
            next_addr += self.counters[i] * self.strides[i]
            
        self.current_addr = next_addr
        return out_addr    
    
    
    def pack_payload(self, strides, counts):
        payload = 0
        axis_width = self.stride_width + self.count_width
        
        for i in range(self.num_axes):
            axis_bits = (strides[i] << self.count_width) | counts[i]
            payload |= axis_bits << (i * axis_width)
        
        return payload
    
    
    def unpack_config_payload(self, payload):
        strides = []
        counts = []
        
        stride_mask = (1 << self.stride_width) - 1
        count_mask = (1 << self.count_width) - 1
        axis_width = self.stride_width + self.count_width
        
        for i in range(self.num_axes):
            shifted_payload = payload >> (i * axis_width)
            count = shifted_payload & count_mask
            stride = (shifted_payload >> self.count_width) & stride_mask
            
            strides.append(stride)
            counts.append(count)
        
        return strides, counts
