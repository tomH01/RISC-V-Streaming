from abc import ABC, abstractmethod
import random as rnd

from enum import IntEnum

class Mode(IntEnum):
    LINEAR = 0
    STRIDED = 1
    

class BaseGeneratorModel(ABC):
    @abstractmethod
    def initialize(self, config_payload, base_addr=0):
        pass
    
    @abstractmethod
    def step(self) -> int:
        pass
    
    @abstractmethod
    def generate_payload(self, window_size) -> int:
        pass


class LinearGeneratorModel(BaseGeneratorModel):
    def __init__(self):
        self.current_addr = 0
        
    def initialize(self, config_payload=None, base_addr=0):
        self.current_addr = base_addr
        
    def step(self) -> int:
        out_addr = self.current_addr
        self.current_addr += 1
        return out_addr
    
    def generate_payload(self, window_size) -> int:
        return 0
        

class StridedGeneratorModel(BaseGeneratorModel):
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
    
    def step(self) -> int:
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
    
    def generate_payload(self, window_size) -> int:
        if window_size <= 0:
            raise ValueError("Window size must be greater than 0.")
        
        factors = self._factorize(window_size)
        counts = self._partition_factors(factors)
        strides_canonical = self._get_canonical_strides(counts)
        
        axis_pairs = list(zip(strides_canonical, counts))
        rnd.shuffle(axis_pairs)
        shuffled_strides, shuffled_counts = zip(*axis_pairs)
        return self.pack_payload(shuffled_strides, shuffled_counts)
    
    def _factorize(self, n):
        """ based on trial division method """
        factors = []
        d = 2
        temp = n
        while d * d <= temp:
            while temp % d == 0:
                factors.append(d)
                temp //= d
            d += 1
        if temp > 1:
            factors.append(temp)
        return factors
    
    def _partition_factors(self, factors):
        counts = [1] * self.num_axes
        for factor in factors:
            counts[rnd.randrange(self.num_axes)] *= factor
        return counts
            
    def _get_canonical_strides(self, counts):
        strides = []
        current_stride = 1
        for count in counts:
            strides.append(current_stride)
            current_stride *= count
        return strides         
    
    
def main():
    window_size = 10
    
    agu = StridedGeneratorModel(count_width=14, stride_width=10, num_axes=4)
    agu.initialize(agu.generate_payload(window_size))

    addrs = []
    for _ in range(window_size):
        addr = agu.step()
        assert addr not in addrs, f"Duplicate address generated: {addr}"
        assert addr < window_size
        addrs.append(addr)
        
    print(f"Generated addresses: {addrs}")    

if __name__ == "__main__":
    main()
