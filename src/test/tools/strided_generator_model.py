

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
        
    def initialize(self, strides, counts, base_addr=0):
        self.base_addr = base_addr
        self.current_addr = base_addr
        
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
