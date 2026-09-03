

class Stream:
    def __init__(
            self, 
            id,
            sensor, 
            interval, 
            total_w, 
            total_h,
            block_w,
            block_h,
            collection_size,
            exec_time,
            **extra
            
        ):
        self.id = id
        self.sensor = sensor
        self.interval = interval
        self.total_w = total_w
        self.total_h = total_h
        self.block_w = block_w
        self.block_h = block_h
        self.collection_size = collection_size
        self.exec_time = exec_time
        self.extra = extra
        
        self.jobs = []
        self.data_map = {}
        
        self.strides = []
        self.counts = []
        
    def handle_collection(self):
        if len(self.data_map) == self.collection_size and all(value != -1 for value in self.data_map.values()):
            next_cpu_done_ptr = next(reversed(self.data_map))
            self.data_map.clear()
            return (self.exec_time, self.id, next_cpu_done_ptr)
        
    def set_fine_tiling_config(self):
        tile_w = int(self.extra['Tile Width (FT)'])
        tile_h = int(self.extra['Tile Height (FT)'])
        
        axes = [
            [tile_w, 1],
            [tile_h, self.block_w],
            [self.block_w // tile_w, tile_w],
            [0, 0]
        ]
        print(f"Stream {self.id}: Fine Tiling Config: {axes}")
        self.counts, self.strides = map(list, zip(*axes)) 
    
    def get_coarse_tiling_config(self):
        pass
        

        