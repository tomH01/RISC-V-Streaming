import random as rnd

from typing import Dict


class ConfigRandomizer:
    def __init__(self, n_streams, m_macros, macro_depth):
        self.n_streams = n_streams
        self.m_macros = m_macros
        self.macro_depth = macro_depth
    
    def generate_configs(self):
        configs = {}
        result_topology = {}
        
        available_macros = list(range(self.m_macros))
        rnd.shuffle(available_macros)    
        
        nb_active_streams = rnd.randint(1, self.n_streams)
            
        active_stream_ids = rnd.sample(range(self.n_streams), nb_active_streams)
        window_sizes, macros_per_window_list = self._generate_window_sizes(nb_active_streams)
        
        for i, stream_idx in enumerate(active_stream_ids):
            required_left_macros = 0
            for s in range(i + 1, len(active_stream_ids)):
                required_left_macros += macros_per_window_list[s] * 2
                    
            max_macros_to_allocate = len(available_macros) - required_left_macros
            multiplier = rnd.randint(2, max_macros_to_allocate // macros_per_window_list[i])
            num_allocated_macros = multiplier * macros_per_window_list[i]
            
            macros = [available_macros.pop() for _ in range(num_allocated_macros)]
            
            topology = {}
            for j in range(num_allocated_macros):
                current_macro = macros[j]
                next_macro = macros[(j + 1) % num_allocated_macros]
                topology[current_macro] = next_macro
                
            configs[stream_idx] = {
                'window_size': window_sizes[i],
                'start_macro': macros[0],
                'topology': topology
            }
            
            result_topology.update(topology)
            
        return configs, result_topology 
                
    def _generate_window_sizes(self, nb_active_streams):
        pool = self.m_macros
        window_sizes = []
        macros_per_window_list = []
        
        for i in range(nb_active_streams):
            streams_left = nb_active_streams - i - 1
            reserved = streams_left * 2
            
            while True:
                window_size = rnd.randint(1, 2 * self.macro_depth)
                macros_per_window = (window_size - 1) // self.macro_depth + 1
                
                if macros_per_window * 2 <= (pool - reserved):
                    window_sizes.append(window_size)
                    macros_per_window_list.append(macros_per_window)
                    pool -= macros_per_window * 2
                    break
                    
        return window_sizes, macros_per_window_list
    