

class StridedGeneratorModel:
    def __init__(self, base_addr, payload, count_width, stride_width, num_axes):
        self.base_addr = base_addr
        self.payload = payload
        
        self.count_width = count_width
        self.stride_width = stride_width
        self.num_axes = num_axes

        self.current_addr = base_addr
        
        strides, counts = self.unpack_payload(payload)
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
    
    def unpack_payload(self, payload):
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
