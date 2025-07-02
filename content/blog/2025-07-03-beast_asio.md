+++
title = '2025 07 03 Beast_asio'
date = 2025-07-03T04:53:06+08:00
draft = true
tags = [ "network" ]

+++




```bash
root@ip-172-31-27-243:~# strace -p $(pgrep FlashKWS)
strace: Process 45835 attached
restart_syscall(<... resuming interrupted read ...>) = 0
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc24880, FUTEX_WAIT_PRIVATE, 2, NULL) = -1 EAGAIN (Resource temporarily unavailable)
futex(0x5565cfc24880, FUTEX_WAKE_PRIVATE, 1) = 0
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
clock_nanosleep(CLOCK_REALTIME, 0, {tv_sec=30, tv_nsec=0}, {tv_sec=11, tv_nsec=822885569}) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted clock_nanosleep ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted restart_syscall ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted restart_syscall ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted restart_syscall ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted restart_syscall ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted restart_syscall ...>) = ? ERESTART_RESTARTBLOCK (Interrupted by signal)
--- SIGWINCH {si_signo=SIGWINCH, si_code=SI_KERNEL} ---
restart_syscall(<... resuming interrupted restart_syscall ...>) = 0
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc24880, FUTEX_WAIT_PRIVATE, 2, NULL) = -1 EAGAIN (Resource temporarily unavailable)
futex(0x5565cfc24880, FUTEX_WAKE_PRIVATE, 1) = 0
clock_nanosleep(CLOCK_REALTIME, 0, {tv_sec=30, tv_nsec=0}, 0x7fffd29dec90) = 0
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
clock_nanosleep(CLOCK_REALTIME, 0, {tv_sec=30, tv_nsec=0}, 0x7fffd29dec90) = 0
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
clock_nanosleep(CLOCK_REALTIME, 0, {tv_sec=30, tv_nsec=0}, 0x7fffd29dec90) = 0
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc24880, FUTEX_WAIT_PRIVATE, 2, NULL) = -1 EAGAIN (Resource temporarily unavailable)
futex(0x5565cfc24880, FUTEX_WAKE_PRIVATE, 1) = 0
socketpair(AF_UNIX, SOCK_STREAM, 0, [14, 15]) = 0
fcntl(14, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(14, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
fcntl(15, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(15, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=14, events=POLLIN}], 1, 0)    = 0 (Timeout)
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
socket(AF_INET6, SOCK_DGRAM, IPPROTO_IP) = 16
close(16)                               = 0
socketpair(AF_UNIX, SOCK_STREAM, 0, [16, 17]) = 0
rt_sigprocmask(SIG_BLOCK, ~[], [], 8)   = 0
clone3({flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, child_tid=0x7ff7bd0ff990, parent_tid=0x7ff7bd0ff990, exit_signal=0, stack=0x7ff7bc8ff000, stack_size=0x7ffc80, tls=0x7ff7bd0ff6c0} => {parent_tid=[48645]}, 88) = 48645
rt_sigprocmask(SIG_SETMASK, [], NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 1) = 0 (Timeout)
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 1) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
close(17)                               = 0
close(16)                               = 0
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 16
setsockopt(16, SOL_TCP, TCP_NODELAY, [1], 4) = 0
fcntl(16, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(16, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
connect(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("54.65.141.133")}, 16) = -1 EINPROGRESS (Operation now in progress)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLOUT}, {fd=14, events=POLLIN}], 2, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLPRI|POLLOUT|POLLWRNORM}], 1, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLOUT}, {fd=14, events=POLLIN}], 2, 198) = 1 ([{fd=16, revents=POLLOUT}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLPRI|POLLOUT|POLLWRNORM}], 1, 0) = 1 ([{fd=16, revents=POLLOUT|POLLWRNORM}])
getsockopt(16, SOL_SOCKET, SO_ERROR, [0], [4]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55774), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
getpeername(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("54.65.141.133")}, [128 => 16]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55774), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
sendto(16, "\26\3\1\2\0\1\0\1\374\3\3\313\214p\354C\16\276\27\212\307\257\22\327\305A\260\244\260\222h\232"..., 517, MSG_NOSIGNAL, NULL, 0) = 517
recvfrom(16, 0x5565d002f603, 5, 0, NULL, NULL) = -1 EAGAIN (Resource temporarily unavailable)
openat(AT_FDCWD, "/etc/ssl/certs/ca-certificates.crt", O_RDONLY) = 17
newfstatat(17, "", {st_mode=S_IFREG|0644, st_size=213777, ...}, AT_EMPTY_PATH) = 0
read(17, "-----BEGIN CERTIFICATE-----\nMIIH"..., 4096) = 4096
read(17, "8B1\nRXxlDPiyN8+sD8+Nb/kZ94/sHvJw"..., 4096) = 4096
read(17, "BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC"..., 4096) = 4096
read(17, "oZIhvcNAQEMBQAwQTELMAkGA1UE\nBhMC"..., 4096) = 4096
read(17, "DCCAgoCggIBAK2Wny2cSkxK\ngXlRmeyK"..., 4096) = 4096
read(17, "aAjMaZ7snkGeRDImeuKHCnE96+RapNLb"..., 4096) = 4096
read(17, "FFQ4ueCyE8S1wF3BqfmI7avSKecs2t\nC"..., 4096) = 4096
read(17, "mdvhFHJlsTmKtdFoqwNxxXnUX/iJY2v7"..., 4096) = 4096
read(17, "t/SyZi4QKPaXWnuWFo8BGS1sbn85WAZk"..., 4096) = 4096
read(17, "dHkwggIiMA0GCSqGSIb3DQEBAQUAA4IC"..., 4096) = 4096
read(17, "2IpHLlOR+Vnb5n\nwXARPbv0+Em34yaXO"..., 4096) = 4096
read(17, "0gQ2VydGlmaWNhdGlvbiBBdXRob3JpdH"..., 4096) = 4096
read(17, "TLkEu\nMScwJQYDVQQLEx5DZXJ0dW0gQ2"..., 4096) = 4096
read(17, "Y2FfMV8yMDIwLmNybDB5oHegdYZzbGRh"..., 4096) = 4096
read(17, "A4IBAQA07XtaPKSUiO8aEXUHL7P+PPoe"..., 4096) = 4096
read(17, "iYWwgUm9vdCBD\nQTAeFw0wNjExMTAwMD"..., 4096) = 4096
read(17, "EwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEw"..., 4096) = 4096
read(17, "9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCi\nE"..., 4096) = 4096
read(17, "xGZsrTie0bBRiKWQzPUwHQYDVR0OBBYE"..., 4096) = 4096
read(17, "ZmVyZW5jZTEfMB0GA1UECxMW\nKGMpIDI"..., 4096) = 4096
read(17, "MIIGSzCCBDOgAwIBAgIRANm1Q3+vqTkP"..., 4096) = 4096
read(17, "aaApJUqlyyvdimYHFngVV3Eb7PVHhPOe"..., 4096) = 4096
read(17, "A1UEChMZR29vZ2xlIFRydXN0IFNlcnZp"..., 4096) = 4096
read(17, "cflK2GwwCgYIKoZIzj0EAwMwUDEk\nMCI"..., 4096) = 4096
read(17, "yCLNhZglqsQY6ZZZZwPA1/cnaKI0aEYd"..., 4096) = 4096
read(17, "LjExMC8GA1UECxMoR28gRGFkZHkgQ2xh"..., 4096) = 4096
read(17, "/JiZ+yykgmvw\nKh+OC19xXFyuQnspiYH"..., 4096) = 4096
read(17, "aSrT2y7HxjbdavYy5LNlDhhDgcGH0tGE"..., 4096) = 4096
read(17, "4i707mV78vH9toxdCim5lSJ9UExyuUmG"..., 4096) = 4096
read(17, "gCyzuFJ0nN6T5U6VR5CmD1/iQMVtCnwr"..., 4096) = 4096
read(17, "wZS5jb20wHhcNMDcxMjEzMTMwODI4Whc"..., 4096) = 4096
read(17, "I3\nFQEEAwIBADAKBggqhkjOPQQDAwNoA"..., 4096) = 4096
read(17, "tP+oGI/hGoiLtk/bdmuYqh7GYVPEi92t"..., 4096) = 4096
read(17, "gxCzAJBgNVBAYTAkJNMRkwFwYDVQQKEx"..., 4096) = 4096
read(17, "ggIKAoICAQChriWyARjcV4g/Ruv5r+Lr"..., 4096) = 4096
read(17, "BHMzAeFw0xMjAxMTIyMDI2MzJaFw00\nM"..., 4096) = 4096
read(17, "ZhcFUZh1++VQLHqe8RT6q9OKPv+RKY9j"..., 4096) = 4096
read(17, "Uk9PVCBDQTIwggEiMA0GCSqGSIb3DQEB"..., 4096) = 4096
read(17, "BCWeZ4WNOaptvolRTnI\nHmX5k/Wq8VLc"..., 4096) = 4096
read(17, "DcAiMI4u8hOscNtybS\nYpOnpSNyByCCY"..., 4096) = 4096
read(17, "Z/5FSuS/hVclcCGfgXcVnrHigHdMWdSL"..., 4096) = 4096
read(17, "6LqjviOvrv1vA+ACOzB2+htt\nQc8Bsem"..., 4096) = 4096
read(17, "SivwKixVA9ZIw+A5OO3yXDw/\nRLyTPWG"..., 4096) = 4096
read(17, "PPyBJUgriOCxLM6AGK/5jYk4Ve6xx6Qd"..., 4096) = 4096
read(17, "EPlcDaMtjNXepUugqD0XBCzYYP2AgWGL"..., 4096) = 4096
read(17, "/HHk484IkzlQsPpTLWPFp5LBk=\n-----"..., 4096) = 4096
read(17, "ekDFQdxh\nVicGaeVyQYHTtgGJoC86cnn"..., 4096) = 4096
read(17, "TkD5OGwDxFa2DK5o=\n-----END CERTI"..., 4096) = 4096
read(17, "ydGlmaWNhdGlvbiBBdXRob3JpdHkwHhc"..., 4096) = 4096
read(17, "c5vMZnT5r7SHpDwCRR5XCOrTdLa\nIR9N"..., 4096) = 4096
read(17, "\n-----END CERTIFICATE-----\n-----"..., 4096) = 4096
read(17, "MxMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ"..., 4096) = 4096
read(17, "MBAf8E\nBTADAQH/MA4GA1UdDwEB/wQEA"..., 4096) = 785
read(17, "", 4096)                      = 0
close(17)                               = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 167) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
recvfrom(16, "\26\3\3\0z", 5, 0, NULL, NULL) = 5
recvfrom(16, "\2\0\0v\3\3\256\303a\224 DiU{\251\374Q\356\241\207X,\217\32a\3515\276?\262?"..., 122, 0, NULL, NULL) = 122
recvfrom(16, "\24\3\3\0\1", 5, 0, NULL, NULL) = 5
recvfrom(16, "\1", 1, 0, NULL, NULL)    = 1
recvfrom(16, "\27\3\3\0$", 5, 0, NULL, NULL) = 5
recvfrom(16, "r\346\3760Y\247qL\371\245*\213\24\6\335#\2\241&\205-O\216x\240 \247\214\272\256\24b"..., 36, 0, NULL, NULL) = 36
recvfrom(16, "\27\3\3\16\275", 5, 0, NULL, NULL) = 5
recvfrom(16, "\353\327\242\231\244J\3631\270\30n\255\332\213\302\256L\334a\226C\232w\6\377x(\256.\16\373\364"..., 3773, 0, NULL, NULL) = 3773
newfstatat(AT_FDCWD, "/etc/ssl/certs/4f7fd3cf.0", 0x7fffd29dd2f0, 0) = -1 ENOENT (No such file or directory)
recvfrom(16, "\27\3\3\1\31", 5, 0, NULL, NULL) = 5
recvfrom(16, "35\0\335\324E  \273\315OVg\324\363R\301\353$351P\206\243\346\246\313b\364\202\331"..., 281, 0, NULL, NULL) = 281
recvfrom(16, "\27\3\3\0005", 5, 0, NULL, NULL) = 5
recvfrom(16, "\372B\252\203\347\3648\17\355v\3570\266\325\233\327\203\233\231\310*!\23g\247\372bG\r}K\206"..., 53, 0, NULL, NULL) = 53
sendto(16, "\24\3\3\0\1\1\27\3\3\0005D)\353\0\276\244\20\16B\335D\240\32\322\377\323D\314\353\234U"..., 64, MSG_NOSIGNAL, NULL, 0) = 64
sendto(16, "\27\3\3\0Q'\245\210\200X(\277\n|qe\337\r\213\t\212X\3529\323\t\221s_\37\316\330"..., 86, MSG_NOSIGNAL, NULL, 0) = 86
getpeername(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("54.65.141.133")}, [128 => 16]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55774), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
getpeername(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("54.65.141.133")}, [128 => 16]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55774), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
sendto(16, "\27\3\3\0M\303\256b\373.\335\276\302\314)\343\264l\221H\374\216;\361\37\16NMB\2\3555"..., 82, MSG_NOSIGNAL, NULL, 0) = 82
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 165) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 1 ([{fd=16, revents=POLLIN|POLLRDNORM}])
recvfrom(16, "\27\3\3\0\256", 5, 0, NULL, NULL) = 5
recvfrom(16, "\304*\216jx\361T}\376@\300A\213\221d\230\325H\215S\3012s,\332\200\253<\1C\25\277"..., 174, 0, NULL, NULL) = 174
brk(0x5565d0155000)                     = 0x5565d0155000
recvfrom(16, "\27\3\3\09", 5, 0, NULL, NULL) = 5
recvfrom(16, "\237\322\343h\220\6\350t\370\216a\301\267\242\236\376_.\21\330\254 \362;\243\30\347hx\200\362 "..., 57, 0, NULL, NULL) = 57
sendto(16, "\27\3\3\0\32=\tA\351J\265G\206L\367\310\216\311\261\254\365\211\371\210\207r\242_\366\270\352", 31, MSG_NOSIGNAL, NULL, 0) = 31
brk(0x5565d0148000)                     = 0x5565d0148000
recvfrom(16, "\27\3\3\0\32", 5, 0, NULL, NULL) = 5
recvfrom(16, "\376\345`\243\211\0\266,e\326\37&\27\f\315tU\251\347\35\4\233\234\246X,", 26, 0, NULL, NULL) = 26
recvfrom(16, 0x5565d0127393, 5, 0, NULL, NULL) = -1 EAGAIN (Resource temporarily unavailable)
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 163) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 1 ([{fd=16, revents=POLLIN|POLLRDNORM}])
recvfrom(16, "\27\3\3\3\21", 5, 0, NULL, NULL) = 5
recvfrom(16, "\r5e\317}\24\340\301\305\4\375\361\303\201\206\2\362\345\351\265a\244\35rZ\305\375x\220f\367\222"..., 785, 0, NULL, NULL) = 785
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
brk(0x5565d0140000)                     = 0x5565d0140000
close(16)                               = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
close(14)                               = 0
close(15)                               = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
socketpair(AF_UNIX, SOCK_STREAM, 0, [14, 15]) = 0
fcntl(14, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(14, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
fcntl(15, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(15, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=14, events=POLLIN}], 1, 0)    = 0 (Timeout)
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
socket(AF_INET6, SOCK_DGRAM, IPPROTO_IP) = 16
close(16)                               = 0
socketpair(AF_UNIX, SOCK_STREAM, 0, [16, 17]) = 0
rt_sigprocmask(SIG_BLOCK, ~[], [], 8)   = 0
clone3({flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, child_tid=0x7ff7bd0ff990, parent_tid=0x7ff7bd0ff990, exit_signal=0, stack=0x7ff7bc8ff000, stack_size=0x7ffc80, tls=0x7ff7bd0ff6c0} => {parent_tid=[48646]}, 88) = 48646
rt_sigprocmask(SIG_SETMASK, [], NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 1) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
close(17)                               = 0
close(16)                               = 0
socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) = 16
setsockopt(16, SOL_TCP, TCP_NODELAY, [1], 4) = 0
fcntl(16, F_GETFL)                      = 0x2 (flags O_RDWR)
fcntl(16, F_SETFL, O_RDWR|O_NONBLOCK)   = 0
connect(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("52.196.51.251")}, 16) = -1 EINPROGRESS (Operation now in progress)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLOUT}, {fd=14, events=POLLIN}], 2, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLPRI|POLLOUT|POLLWRNORM}], 1, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLOUT}, {fd=14, events=POLLIN}], 2, 199) = 1 ([{fd=16, revents=POLLOUT}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLPRI|POLLOUT|POLLWRNORM}], 1, 0) = 1 ([{fd=16, revents=POLLOUT|POLLWRNORM}])
getsockopt(16, SOL_SOCKET, SO_ERROR, [0], [4]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55818), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
getpeername(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("52.196.51.251")}, [128 => 16]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55818), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
getpid()                                = 45835
sendto(16, "\26\3\1\2\0\1\0\1\374\3\3\277R\322sh\303\341eT\374\232\254\t6(\356\341D-\320!"..., 517, MSG_NOSIGNAL, NULL, 0) = 517
recvfrom(16, 0x5565d011f383, 5, 0, NULL, NULL) = -1 EAGAIN (Resource temporarily unavailable)
openat(AT_FDCWD, "/etc/ssl/certs/ca-certificates.crt", O_RDONLY) = 17
newfstatat(17, "", {st_mode=S_IFREG|0644, st_size=213777, ...}, AT_EMPTY_PATH) = 0
read(17, "-----BEGIN CERTIFICATE-----\nMIIH"..., 4096) = 4096
read(17, "8B1\nRXxlDPiyN8+sD8+Nb/kZ94/sHvJw"..., 4096) = 4096
read(17, "BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC"..., 4096) = 4096
read(17, "oZIhvcNAQEMBQAwQTELMAkGA1UE\nBhMC"..., 4096) = 4096
read(17, "DCCAgoCggIBAK2Wny2cSkxK\ngXlRmeyK"..., 4096) = 4096
read(17, "aAjMaZ7snkGeRDImeuKHCnE96+RapNLb"..., 4096) = 4096
read(17, "FFQ4ueCyE8S1wF3BqfmI7avSKecs2t\nC"..., 4096) = 4096
read(17, "mdvhFHJlsTmKtdFoqwNxxXnUX/iJY2v7"..., 4096) = 4096
read(17, "t/SyZi4QKPaXWnuWFo8BGS1sbn85WAZk"..., 4096) = 4096
read(17, "dHkwggIiMA0GCSqGSIb3DQEBAQUAA4IC"..., 4096) = 4096
read(17, "2IpHLlOR+Vnb5n\nwXARPbv0+Em34yaXO"..., 4096) = 4096
read(17, "0gQ2VydGlmaWNhdGlvbiBBdXRob3JpdH"..., 4096) = 4096
read(17, "TLkEu\nMScwJQYDVQQLEx5DZXJ0dW0gQ2"..., 4096) = 4096
read(17, "Y2FfMV8yMDIwLmNybDB5oHegdYZzbGRh"..., 4096) = 4096
read(17, "A4IBAQA07XtaPKSUiO8aEXUHL7P+PPoe"..., 4096) = 4096
read(17, "iYWwgUm9vdCBD\nQTAeFw0wNjExMTAwMD"..., 4096) = 4096
read(17, "EwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEw"..., 4096) = 4096
read(17, "9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCi\nE"..., 4096) = 4096
read(17, "xGZsrTie0bBRiKWQzPUwHQYDVR0OBBYE"..., 4096) = 4096
read(17, "ZmVyZW5jZTEfMB0GA1UECxMW\nKGMpIDI"..., 4096) = 4096
read(17, "MIIGSzCCBDOgAwIBAgIRANm1Q3+vqTkP"..., 4096) = 4096
read(17, "aaApJUqlyyvdimYHFngVV3Eb7PVHhPOe"..., 4096) = 4096
read(17, "A1UEChMZR29vZ2xlIFRydXN0IFNlcnZp"..., 4096) = 4096
read(17, "cflK2GwwCgYIKoZIzj0EAwMwUDEk\nMCI"..., 4096) = 4096
read(17, "yCLNhZglqsQY6ZZZZwPA1/cnaKI0aEYd"..., 4096) = 4096
read(17, "LjExMC8GA1UECxMoR28gRGFkZHkgQ2xh"..., 4096) = 4096
read(17, "/JiZ+yykgmvw\nKh+OC19xXFyuQnspiYH"..., 4096) = 4096
read(17, "aSrT2y7HxjbdavYy5LNlDhhDgcGH0tGE"..., 4096) = 4096
read(17, "4i707mV78vH9toxdCim5lSJ9UExyuUmG"..., 4096) = 4096
read(17, "gCyzuFJ0nN6T5U6VR5CmD1/iQMVtCnwr"..., 4096) = 4096
read(17, "wZS5jb20wHhcNMDcxMjEzMTMwODI4Whc"..., 4096) = 4096
read(17, "I3\nFQEEAwIBADAKBggqhkjOPQQDAwNoA"..., 4096) = 4096
read(17, "tP+oGI/hGoiLtk/bdmuYqh7GYVPEi92t"..., 4096) = 4096
read(17, "gxCzAJBgNVBAYTAkJNMRkwFwYDVQQKEx"..., 4096) = 4096
read(17, "ggIKAoICAQChriWyARjcV4g/Ruv5r+Lr"..., 4096) = 4096
read(17, "BHMzAeFw0xMjAxMTIyMDI2MzJaFw00\nM"..., 4096) = 4096
read(17, "ZhcFUZh1++VQLHqe8RT6q9OKPv+RKY9j"..., 4096) = 4096
read(17, "Uk9PVCBDQTIwggEiMA0GCSqGSIb3DQEB"..., 4096) = 4096
read(17, "BCWeZ4WNOaptvolRTnI\nHmX5k/Wq8VLc"..., 4096) = 4096
read(17, "DcAiMI4u8hOscNtybS\nYpOnpSNyByCCY"..., 4096) = 4096
read(17, "Z/5FSuS/hVclcCGfgXcVnrHigHdMWdSL"..., 4096) = 4096
read(17, "6LqjviOvrv1vA+ACOzB2+htt\nQc8Bsem"..., 4096) = 4096
read(17, "SivwKixVA9ZIw+A5OO3yXDw/\nRLyTPWG"..., 4096) = 4096
read(17, "PPyBJUgriOCxLM6AGK/5jYk4Ve6xx6Qd"..., 4096) = 4096
read(17, "EPlcDaMtjNXepUugqD0XBCzYYP2AgWGL"..., 4096) = 4096
read(17, "/HHk484IkzlQsPpTLWPFp5LBk=\n-----"..., 4096) = 4096
read(17, "ekDFQdxh\nVicGaeVyQYHTtgGJoC86cnn"..., 4096) = 4096
read(17, "TkD5OGwDxFa2DK5o=\n-----END CERTI"..., 4096) = 4096
read(17, "ydGlmaWNhdGlvbiBBdXRob3JpdHkwHhc"..., 4096) = 4096
read(17, "c5vMZnT5r7SHpDwCRR5XCOrTdLa\nIR9N"..., 4096) = 4096
read(17, "\n-----END CERTIFICATE-----\n-----"..., 4096) = 4096
read(17, "MxMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ"..., 4096) = 4096
read(17, "MBAf8E\nBTADAQH/MA4GA1UdDwEB/wQEA"..., 4096) = 785
read(17, "", 4096)                      = 0
close(17)                               = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 169) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
recvfrom(16, "\26\3\3\0z", 5, 0, NULL, NULL) = 5
recvfrom(16, "\2\0\0v\3\3+&\230K\3\6\316\374\346\223\240\2615r\360U\321C\351K\367\212\274\6\34\303"..., 122, 0, NULL, NULL) = 122
recvfrom(16, "\24\3\3\0\1", 5, 0, NULL, NULL) = 5
recvfrom(16, "\1", 1, 0, NULL, NULL)    = 1
recvfrom(16, "\27\3\3\0$", 5, 0, NULL, NULL) = 5
recvfrom(16, "\325R\233\240Y\331\16\\iPY\362}\17\312\320\210\263\231\305\271\37\311\365\32\360\217\317\257\235\223\234"..., 36, 0, NULL, NULL) = 36
recvfrom(16, "\27\3\3\16\275", 5, 0, NULL, NULL) = 5
recvfrom(16, "\206\204\2\375)\215\347gZa\343P\2702\231\315\206A\304\202\212+X]\375y\35\0312\31\\\34"..., 3773, 0, NULL, NULL) = 3773
newfstatat(AT_FDCWD, "/etc/ssl/certs/4f7fd3cf.0", 0x7fffd29dd2f0, 0) = -1 ENOENT (No such file or directory)
recvfrom(16, "\27\3\3\1\31", 5, 0, NULL, NULL) = 5
recvfrom(16, "\202>\305p\34\177\235\204I\372U\267\356\225S\230\224\306\237|\211\235;\376s\315\317\247v\211{\4"..., 281, 0, NULL, NULL) = 281
recvfrom(16, "\27\3\3\0005", 5, 0, NULL, NULL) = 5
recvfrom(16, "c\345\307\342\256%\17u\202{\353\245\302R\272:\347+\375%\302^&\205\353\367<\327\350M\253`"..., 53, 0, NULL, NULL) = 53
sendto(16, "\24\3\3\0\1\1\27\3\3\0005\351\215H\341OH\202\307*L\325\340\303\252\225\n\213\217*P."..., 64, MSG_NOSIGNAL, NULL, 0) = 64
sendto(16, "\27\3\3\0Q\5w4\300o\251\352\327\270\230\304\7e\334\254:*\222\270\311\377\242\321\333\32\\\330"..., 86, MSG_NOSIGNAL, NULL, 0) = 86
getpeername(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("52.196.51.251")}, [128 => 16]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55818), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
getpeername(16, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("52.196.51.251")}, [128 => 16]) = 0
getsockname(16, {sa_family=AF_INET, sin_port=htons(55818), sin_addr=inet_addr("172.31.27.243")}, [128 => 16]) = 0
sendto(16, "\27\3\3\0M\0\26\256\243m\2468\364\323\227\232X@\26500\37j\267\242\262\27SV<@\355"..., 82, MSG_NOSIGNAL, NULL, 0) = 82
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 166) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 1 ([{fd=16, revents=POLLIN|POLLRDNORM}])
recvfrom(16, "\27\3\3\0\256", 5, 0, NULL, NULL) = 5
recvfrom(16, "\336Q\222s\266\347 \22v\30dfQ\331\200}&\255\257\226\261\324\347W\317\272\216\353\177O \304"..., 174, 0, NULL, NULL) = 174
recvfrom(16, "\27\3\3\09", 5, 0, NULL, NULL) = 5
recvfrom(16, "\4\310\336\314\325\275C3\305\351\33C\204\17\rT\t\n\254\357\275G)\223h \246z\33\32\362M"..., 57, 0, NULL, NULL) = 57
sendto(16, "\27\3\3\0\32\254-\251\256>\251\336]\355<;\336\201\4\370\221\262\346\200\335\24Q\305\20w\262", 31, MSG_NOSIGNAL, NULL, 0) = 31
recvfrom(16, "\27\3\3\0\32", 5, 0, NULL, NULL) = 5
recvfrom(16, "\231\275\374-\361\33\3044\247z\334\261y\225\4\r\177R \16\271/r\350\327\364", 26, 0, NULL, NULL) = 26
recvfrom(16, 0x5565d01299c3, 5, 0, NULL, NULL) = -1 EAGAIN (Resource temporarily unavailable)
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 0 (Timeout)
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN}, {fd=14, events=POLLIN}], 2, 165) = 1 ([{fd=16, revents=POLLIN}])
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
poll([{fd=16, events=POLLIN|POLLPRI|POLLRDNORM|POLLRDBAND}], 1, 0) = 1 ([{fd=16, revents=POLLIN|POLLRDNORM}])
recvfrom(16, "\27\3\3\2\377", 5, 0, NULL, NULL) = 5
recvfrom(16, "@\370D\10\1\326W\206\343\315\22\357M5F;\177\230\221\3645\277\233\31C\276\314'\213\261$\301"..., 767, 0, NULL, NULL) = 767
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
close(16)                               = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, NULL, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
close(14)                               = 0
close(15)                               = 0
rt_sigaction(SIGPIPE, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=SA_RESTORER, sa_restorer=0x7ff7c085b050}, NULL, 8) = 0
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d0, FUTEX_WAKE_PRIVATE, 1) = 1
futex(0x5565cfc248d4, FUTEX_WAKE_PRIVATE, 1) = 1

```