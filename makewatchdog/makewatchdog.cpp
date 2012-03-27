/*

  Copyright (c) 2012 Lubos Lunak <l.lunak@suse.cz>

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation
  the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.

*/

#include <algorithm>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <vector>

//#define DEBUG

using namespace std;

static int usage( const char* argv0 )
    {
    printf( "Usage: %s [timeout] [maxAttempts] -- [make command...]\n", argv0 );
    return 0;
    }

const int FAILURE = 3; // do not use 1 or 2 (check exit values make uses)
#define NAME "Make watchdog: "

struct ProcInfo
    {
    pid_t pid;
    pid_t parent;
    string cmdline;
    };

typedef vector< ProcInfo > ProcInfoList;

static ProcInfoList findAllProcesses()
    {
    ProcInfoList procInfos;
    DIR* dir = opendir( "/proc/" );
    if( dir == NULL )
        {
        fprintf( stderr, NAME "Cannot read /proc.\n" );
        return procInfos;
        }
    while( dirent* entry = readdir( dir ))
        {
        char buf[ 16384 ];
        ProcInfo procInfo;
        procInfo.pid = atoi( entry->d_name );
        if( procInfo.pid == 0 )
            continue;
        if( FILE* f = fopen(( string( "/proc/" ) + entry->d_name + "/stat" ).c_str(), "r" ))
            {
            int size = fread( buf, 1, sizeof( buf ) - 1, f );
            if( ferror( f ))
                {
#ifdef DEBUG
                fprintf( stderr, "Cannot read stat for %s\n", entry->d_name );
#endif
                fclose( f );
                continue;
                }
            buf[ size ] = '\0';
            fclose( f );
            procInfo.parent = 0;
            if( const char* lparen = strchr( buf, '(' ))
                if( const char* rparen = strrchr( lparen, ')' ))
                    sscanf( rparen + 2, "%*c %d", &procInfo.parent );
            if( procInfo.parent == 0 )
                continue;
            if( procInfo.pid == procInfo.parent )
                continue; // just in case
            }
        else
            {
#ifdef DEBUG
            fprintf( stderr, "Cannot open stat for %s\n", entry->d_name );
#endif
            continue;
            }
        if( FILE* f = fopen(( string( "/proc/" ) + entry->d_name + "/cmdline" ).c_str(), "r" ))
            {
            *buf = '\0';
            fscanf( f, "%s", buf );
            fclose( f );
            procInfo.cmdline = buf;
            }
        else
            { // not an error
#ifdef DEBUG
            fprintf( stderr, "Cannot read cmdline for %s\n", entry->d_name );
#endif
            }
        // ok
        procInfos.push_back( procInfo );
        }
    closedir( dir );
    return procInfos;
    }

static void findToKillRecursive( pid_t parent, const ProcInfoList& allProcesses, ProcInfoList* toKill )
    {
    for( unsigned int i = 0;
         i < allProcesses.size();
         ++i )
        if( allProcesses[ i ].parent == parent )
            {
            findToKillRecursive( allProcesses[ i ].pid, allProcesses, toKill );
            toKill->push_back( allProcesses[ i ] );
            }
    }

static vector< ProcInfo > findToKill( pid_t topParent )
    {
    ProcInfoList allProcesses = findAllProcesses();
    ProcInfoList toKill;
    findToKillRecursive( topParent, allProcesses, &toKill );
#ifdef DEBUG
    bool found = false;
#endif
    for( unsigned int i = 0;
         i < allProcesses.size();
         ++i )
        if( allProcesses[ i ].pid == topParent )
            {
            toKill.push_back( allProcesses[ i ] );
#ifdef DEBUG
            found = true;
#endif
            break;
            }
#ifdef DEBUG
    if( !found )
        fprintf( stderr, "Top parent process info not found.\n" );
#endif
    return toKill;
    }

// I hope I got this one right
static int makeExitCode( int status )
    {
    if( WIFEXITED( status ))
        return WEXITSTATUS( status );
    if( WIFSIGNALED( status ))
        return 128 + WTERMSIG( status );
    return FAILURE;
    }

enum KillStatus
    {
    SuccessfullExit, // exited cleanly
    KilledInterrupted, // was interrupted (cleanly)
    KilledForced       // force killed (not clean)
    };

static int killMake( pid_t pid, KillStatus* killed )
    {
#ifdef DEBUG
    fprintf( stderr, "Going to kill pid %d.\n", pid );
#endif
    ProcInfoList toKill = findToKill( pid );
    // SIGINT first
    for( unsigned i = 0;
         i < toKill.size();
         ++i )
        kill( toKill[ i ].pid, SIGINT );
    time_t t = time( NULL );
    while( t + 10 > time( NULL ))
        sleep( 2 ); // may get interrupted by a signal
    int status;
    bool pidHasFinished = false;
    // need to clean up the top parent
    if( waitpid( pid, &status, WNOHANG ) >= 0 )
        {
        pidHasFinished = true;
        *killed = KilledInterrupted;
        }
    // now forcibly
    for( unsigned i = 0;
         i < toKill.size();
         ++i )
        {
        if( kill( toKill[ i ].pid, 0 ) == 0 ) // still alive?
            {
            *killed = KilledForced; // unclear cleanup
            fprintf( stderr, NAME "Process %d not interrupted, forcibly killing.\n", toKill[ i ].pid );
            fprintf( stderr, NAME "Cmdline: %s\n", toKill[ i ].cmdline.c_str());
            kill( toKill[ i ].pid, SIGKILL );
            }
        }
    if( !pidHasFinished )
        waitpid( pid, &status, 0 );
    return makeExitCode( status );
    }

bool makeNonBlocking( int fd )
    {
    int options = fcntl( fd, F_GETFL );
    if( options < 0 )
        {
        perror( NAME "fcntl( F_GETFL )" );
        return false;
        }
    if( fcntl( fd, F_SETFL, O_NONBLOCK | O_CLOEXEC ) < 0 )
        {
        perror( NAME "fcntl( F_SETFL )" );
        return false;
        }
    return true;
    }

static int childPipeWrite;

static void childHandler( int )
    {
    char c = '\0';
    write( childPipeWrite, &c, 1 );
    }

void copyFdData( int fdIn, int fdOut )
    {
    char buf[ 4096 ];
#ifdef DEBUG
    fprintf( stderr, "Activity in output fd %d.\n", fdOut );
#endif
    while( int len = read( fdIn, buf, sizeof( buf )))
        {
        if( len < 0 )
            {
            if( errno == EINTR )
                continue;
            if( errno == EAGAIN )
                return;
            perror( NAME "read()" );
            return; // TODO ?
            }
        for( int written = 0;
             written < len;
             ++written )
            {
            // TODO SIGPIPE handling? It seems that simply getting killed
            // should be ok.
            int tmp = write( fdOut, buf + written, len - written );
            if( tmp < 0 )
                {
                if( errno == EINTR || errno == EAGAIN )
                    continue;
                perror( NAME "write()" );
                }
            written += tmp;
            }
        }
    }

static int watchMake( pid_t pid, KillStatus* killed, int timeout, int stdoutFd, int stderrFd )
    {
    int pipeFd[ 2 ];
    if( pipe( pipeFd ) < 0 )
        {
        perror( NAME "pipe()" );
        return FAILURE;
        }
    childPipeWrite = pipeFd[ 1 ];
    int childPipeRead = pipeFd[ 0 ];
    if( !makeNonBlocking( childPipeRead ))
        return FAILURE;
    struct sigaction act;
    act.sa_handler = childHandler;
    sigemptyset( &act.sa_mask );
    act.sa_flags = SA_NOCLDSTOP;
#ifdef SA_RESTART
    act.sa_flags |= SA_RESTART;
#endif
    sigaction( SIGCHLD, &act, NULL );
    time_t lastActivity = time( NULL );
    for(;;)
        {
        fd_set in;
        FD_ZERO( &in );
        FD_SET( stdoutFd, &in );
        FD_SET( stderrFd, &in );
        FD_SET( childPipeRead, &in );
        struct timeval timeoutStruct;
        timeoutStruct.tv_usec = 0;
        timeoutStruct.tv_sec = max< long >( lastActivity + timeout - time( NULL ) + 1, 1 );
        int maxFd = max( childPipeRead, max( stdoutFd, stderrFd ));
#ifdef DEBUG
        fprintf( stderr, "Sleeping for max %ld seconds.\n", timeoutStruct.tv_sec );
#endif
        if( select( maxFd + 1, &in, NULL, NULL, &timeoutStruct ) < 0 )
            {
            if( errno == EINTR || errno == EAGAIN )
                continue;
            perror( "Make watchdog, select() : " );
            return FAILURE;
            }
        if( FD_ISSET( stdoutFd, &in ))
            {
            copyFdData( stdoutFd, STDOUT_FILENO );
            lastActivity = time( NULL );
            }
        if( FD_ISSET( stderrFd, &in ))
            {
            copyFdData( stderrFd, STDERR_FILENO );
            lastActivity = time( NULL );
            }
        if( FD_ISSET( childPipeRead, &in ))
            {
            char buf[ 1 ];
            if( read( childPipeRead, buf, 1 ) > 0 )
                {
#ifdef DEBUG
                fprintf( stderr, "Child exited\n" );
#endif
                int status;
                while( waitpid( pid, &status, 0 ) < 0 && errno == EINTR )
                    ;
                signal( SIGCHLD, SIG_DFL );
                return makeExitCode( status );
                }
            }
        if( lastActivity + timeout < time( NULL ))
            { // timeout
#ifdef DEBUG
            fprintf( stderr, "Activity timeout.\n" );
#endif
            signal( SIGCHLD, SIG_DFL );
            return killMake( pid, killed );
            }
        }
    }

static int runMake( int argc, char** argv, KillStatus* killed, int timeout )
    {
    int stdoutPipe[ 2 ];
    int stderrPipe[ 2 ];
    if( pipe( stdoutPipe ) < 0 )
        {
        perror( NAME "pipe()" );
        return FAILURE;
        }
    if( pipe( stderrPipe ) < 0 )
        {
        perror( NAME "pipe()" );
        return FAILURE;
        }
    int stdoutRead = stdoutPipe[ 0 ];
    int stdoutWrite = stdoutPipe[ 1 ];
    int stderrRead = stderrPipe[ 0 ];
    int stderrWrite = stderrPipe[ 1 ];
    if( !makeNonBlocking( stdoutRead ))
        return FAILURE;
    if( !makeNonBlocking( stderrRead ))
        return FAILURE;
    pid_t pid = fork();
    switch( pid )
        {
        default: // parent
            close( stdoutWrite );
            close( stderrWrite );
            return watchMake( pid, killed, timeout, stdoutRead, stderrRead );
        case 0: // child
            close( stdoutRead );
            close( stderrRead );
            if( !dup2( stdoutWrite, STDOUT_FILENO ))
                {
                perror( NAME "dup2()" );
                exit( FAILURE );
                }
            if( !dup2( stderrWrite, STDERR_FILENO ))
                {
                perror( NAME "dup2()" );
                exit( FAILURE );
                }
            close( stdoutWrite );
            close( stderrWrite );
            execvp( argv[ 0 ], argv );
            break;
        case -1: // failure
            perror( NAME "fork()" );
            break;
        }
    fprintf( stderr, NAME "Make command invocation failed.\n" );
    return FAILURE;
    }

int main( int argc, char** argv )
    {
    if( argc < 5 || strcmp( argv[ 3 ], "--" ) != 0 )
        return usage( argv[ 0 ] );
    int timeout = atoi( argv[ 1 ] );
    int attempts = atoi( argv[ 2 ] );
    int exitcode = 0;
    for( int attempt = 1;
         attempt <= attempts;
         ++attempt )
        {
        KillStatus killed = SuccessfullExit;
        exitcode = runMake( argc - 4, argv + 4, &killed, timeout );
        switch( killed )
            {
            case SuccessfullExit:
                attempt = attempts + 1; // break out of the loop
                break;
            case KilledInterrupted:
                if( attempt == attempts )
                    fprintf( stderr, NAME "Error: Make command timed out, maximum number of attempts reached,"
                        " failing, exit code %d.\n", exitcode );
                else
                    fprintf( stderr, NAME "Error: Make command timed out, attempt %d/%d, interrupting"
                        " and retrying.\n", attempt, attempts );
                break;
            case KilledForced:
                fprintf( stderr, NAME "Error: Make command timed out, force killed, failing,"
                    " exit code %d\n", exitcode );
                attempt = attempts + 1; // break out of the loop
                break;
            }
        }
    return exitcode;
    }
