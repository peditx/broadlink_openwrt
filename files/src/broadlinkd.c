// src/broadlinkd.c
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <libubox/uloop.h>

static struct uloop_fd ufd;
static int running = 1;

static void signal_handler(int signo)
{
    running = 0;
    uloop_end();
}

int main(int argc, char **argv)
{
    uloop_init();
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    printf("Broadlink Daemon Started\n");
    
    while(running) {
        // Main loop logic
        sleep(1);
    }
    
    printf("Broadlink Daemon Stopped\n");
    return 0;
}
