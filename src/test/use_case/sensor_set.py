import csv

from stream import Stream


class SensorSet:
    def __init__(self, n_streams, m_macros, macro_depth):
        self.streams = []

        self.n_streams = n_streams
        self.m_macros = m_macros
        self.macro_depth = macro_depth

    def import_streams(self, file_path, mode='FT'):
        self.streams = []
        
        common_keys = {
            'Sensor', 'Interval', 'Total Width', 'Total Height',
            f'Block Width ({mode})', f'Block Height ({mode})',
            f'Collection Size ({mode})', f'Execution Time ({mode})'
        }
        
        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter=';')
            
            for stream_id, row in enumerate(reader):
                extra = {k: v for k, v in row.items() if k not in common_keys}
                
                print(f"Importing stream {stream_id}: Sensor={row['Sensor']}, Interval={row['Interval']}, Total Width={row['Total Width']}, Total Height={row['Total Height']}, Block Width={row[f'Block Width ({mode})']}, Block Height={row[f'Block Height ({mode})']}, Collection Size={row[f'Collection Size ({mode})']}, Execution Time={row[f'Execution Time ({mode})']}, Extra={extra}")
                
                stream = Stream(
                    id=stream_id,
                    sensor=row['Sensor'],
                    interval=int(row['Interval']),
                    total_w=int(row['Total Width']),
                    total_h=int(row['Total Height']),
                    block_w=int(row[f'Block Width ({mode})']),
                    block_h=int(row[f'Block Height ({mode})']),
                    collection_size=int(row[f'Collection Size ({mode})']),
                    exec_time=int(row[f'Execution Time ({mode})']),
                    **extra
                )
                self.streams.append(stream)
                
        assert len(self.streams) == self.n_streams, f"Expected {self.n_streams} streams, but got {len(self.streams)}"        
        
    def generate_configs(self, verbose=False):
        configs = {}
        result_topology = {}
        current_macro_id = 0
        
        for i, stream in enumerate(self.streams):
            block_size = stream.block_w * stream.block_h
            
            macros_per_window = (block_size - 1) // self.macro_depth + 1
            
            num_allocated_macros = macros_per_window * 2
            
            if current_macro_id + num_allocated_macros > self.m_macros:
                raise ValueError(f"Not enough macros to allocate for stream {i}. Required: {num_allocated_macros}, Available: {self.m_macros - current_macro_id}")
            
            macros = list(range(current_macro_id, current_macro_id + num_allocated_macros))
            current_macro_id += num_allocated_macros

            topology = {}
            for j in range(num_allocated_macros):
                current_macro = macros[j]
                next_macro = macros[(j + 1) % num_allocated_macros]
                topology[current_macro] = next_macro
                
            configs[i] = {
                'window_size': block_size,
                'start_macro': macros[0],
                'topology': topology,
                'interval': stream.interval
            }
            
            result_topology.update(topology)
            
        if verbose:
            print("Generated Configs from CSV:")
            for stream_id, cfg in configs.items():
                print(f"Stream {stream_id} ({self.streams[stream_id].sensor}): {cfg}")
            print("Resulting Topology:", result_topology)
            
        return configs, result_topology
    
    def insert_data(self, addr, data):
        for stream_id, stream in enumerate(self.streams):
            if addr in stream.data_map:
                stream.data_map[addr] = data
                return stream
            
