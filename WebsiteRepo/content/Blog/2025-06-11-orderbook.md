+++
title = '2025 06 11 Orderbook'
date = 2025-06-11T21:32:27+08:00
draft = false
+++



Samples: 59K of event 'context-switches', Event count (approx.): 12724883
  Children      Self  Command          Shared Object                                    Symbol
+   99.83%    99.83%  strategyTrade    [kernel.kallsyms]                                [k] schedule
+   99.76%     0.00%  strategyTrade    [kernel.kallsyms]                                [k] entry_SYSCALL_64_after_hwf
+   99.76%     0.00%  strategyTrade    [kernel.kallsyms]                                [k] do_syscall_64
+   99.70%     0.00%  strategyTrade    libstdc++.so.6.0.30                              [.] 0x00007f689e0d44a3
+   99.70%     0.00%  strategyTrade    strategyTrade                                    [.] std::this_thread::yield
+   99.70%     0.00%  strategyTrade    libc.so.6                                        [.] __sched_yield
+   99.69%     0.00%  strategyTrade    [kernel.kallsyms]                                [k] __x64_sys_sched_yield
+   49.86%     0.00%  strategyTrade    strategyTrade                                    [.] std::thread::_State_impl<s
+   49.86%     0.00%  strategyTrade    strategyTrade                                    [.] std::thread::_Invoker<std:
+   49.86%     0.00%  strategyTrade    strategyTrade                                    [.] std::thread::_Invoker<std:
+   49.86%     0.00%  strategyTrade    strategyTrade                                    [.] std::__invoke<void (StraTr
+   49.86%     0.00%  strategyTrade    strategyTrade                                    [.] std::__invoke_impl<void, v
+   49.86%     0.00%  strategyTrade    strategyTrade                                    [.] StraTrade::LockFreeEventBu
+   49.85%     0.00%  strategyTrade    strategyTrade                                    [.] std::thread::_State_impl<s
+   49.85%     0.00%  strategyTrade    strategyTrade                                    [.] std::thread::_Invoker<std:
+   49.85%     0.00%  strategyTrade    strategyTrade                                    [.] std::thread::_Invoker<std:
+   49.85%     0.00%  strategyTrade    strategyTrade                                    [.] std::__invoke<void (StraTr
+   49.85%     0.00%  strategyTrade    strategyTrade                                    [.] std::__invoke_impl<void, v
+   49.85%     0.00%  strategyTrade    strategyTrade                                    [.] StraTrade::ExecutionEngine
     0.07%     0.00%  strategyTrade    [kernel.kallsyms]                                [k] exit_to_user_mode_prepare
     0.07%     0.07%  quote_source     [kernel.kallsyms]                                [k] schedule
     0.07%     0.00%  strategyTrade    [kernel.kallsyms]                                [k] irqentry_exit_to_user_mode
     0.07%     0.00%  quote_source     libstdc++.so.6.0.30                              [.] 0x00007ff56fed44a3
     0.07%     0.00%  quote_source     quote_source                                     [.] std::thread::_State_impl<s
     0.07%     0.00%  quote_source     quote_source                                     [.] std::thread::_Invoker<std:
     0.07%     0.00%  quote_source     quote_source                                     [.] std::thread::_Invoker<std:
