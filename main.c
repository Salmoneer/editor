#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#define KEY_ENTER '\r'
#define KEY_BACKSPACE 127

#define CTRL_PLUS(k) ((k) & 0x1f)

char *buffer = NULL;
size_t buffer_size = 0;
size_t cursor_pos = 0;

int term_rows;
int term_cols;

struct termios reset_termios;

/* Debug */

void die(const char *error) {
    perror(error);
    exit(EXIT_FAILURE);
}

/* Terminal io */

// NOTE: Don't call this, it is automatically scheduled by enable_raw_mode
void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &reset_termios);
}

// https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
void enable_raw_mode() {
    if (tcgetattr(STDIN_FILENO, &reset_termios) == -1) die("tcgetattr");
    atexit(disable_raw_mode);

    struct termios raw = reset_termios;
    raw.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);

    raw.c_cc[VMIN] = 0;             // Minimum characters to read
    raw.c_cc[VTIME] = 1;            // Delay when reading in 10ths of a second

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) die("tcsetattr");
}

void update_term_size() {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == -1) die("ioctl");

    term_rows = w.ws_row;
    term_cols = w.ws_col;
}

/* String manipulation */

char *string_replace(const char *string, const char *find, const char *replace) {
    int str_len = strlen(string);
    int find_len = strlen(find);
    int replace_len = strlen(replace);

    int replacements = 0;
    const char *match = strstr(string, find);
    while (match != NULL) {
        replacements++;
        match += find_len;
        match = strstr(match, find);
    }

    char *out = malloc(str_len + (replace_len - find_len) * replacements + 1);
    if (out == NULL) die("string_replace malloc");

    int i = 0;
    match = string;

    while ((match = strstr(match, find)) != NULL) {
        memcpy(out + i, string, match - string);
        i += match - string;

        memcpy(out + i, replace, replace_len);
        i += replace_len;

        match += find_len;
        string = match;
    }

    strcpy(out + i, string);

    return out;
}

/* Printing */

void write_char(char c) {
    if (write(STDOUT_FILENO, &c, 1) != 1) die("write_char");
}

void write_string(const char *string) {
    if (write(STDOUT_FILENO, string, strlen(string)) != strlen(string)) die("write_string");
}

void write_unix_string(const char *string) {
    char *writable_string = string_replace(string, "\n", "\r\n");
    write_string(writable_string);
    free(writable_string);
}

void clear_screen() {
    write_string("\x1b[2J");
    write_string("\x1b[1;1H");
}

/* Processing */

char read_key_press() {
    int nread;
    char c;

    while ((nread = read(STDIN_FILENO, &c, 1)) != 1) {
        if (nread == -1) die("read");
    }

    return c;
}

void handle_key_press() {
    char c = read_key_press();

    if (c == CTRL_PLUS('q')) {
        clear_screen();
        exit(0);
    } else if (!iscntrl(c)) {
        buffer[cursor_pos++] = c;
        write_char(c);
    } else if (c == KEY_ENTER) {
        buffer[cursor_pos++] = '\n';
        write_string("\r\n");
    } else if (c == KEY_BACKSPACE) {
        // TODO: Implement backspace
    }
}

/* Main */

int main() {
    enable_raw_mode();
    clear_screen();
    update_term_size();

    // TODO: Abstract this so I don't have to look at it
    buffer_size = 1024;
    buffer = malloc(buffer_size * sizeof(buffer[0]));
    for (int i = 0; i < buffer_size; i++) {
        buffer[i] = '\0';
    }

    while(1) {
        handle_key_press();
    }

    return 0;
}
