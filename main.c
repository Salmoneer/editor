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

struct row {
    size_t size;
    char *data;
};

struct {
    size_t n_rows;
    struct row *rows;

    size_t cx;
    size_t cy;
} buffer;

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

/* Buffer manipulation */

void init_row(struct row *row) {
    row->size = 0;
    row->data = malloc(0);
}

void init_buffer() {
    buffer.n_rows = 1;
    buffer.rows = malloc(buffer.n_rows * sizeof(struct row));
    init_row(&buffer.rows[0]);

    buffer.cx = 0;
    buffer.cy = 0;
}


void insert_char(struct row *row, int index, char c) {
    row->size++;
    row->data = realloc(row->data, row->size);
    memmove(&row->data[index + 1], &row->data[index], row->size - index - 1);
    row->data[index] = c;
}

void remove_char(struct row *row, int index) {
    row->size--;
    memmove(&row->data[index], &row->data[index + 1], 1);
}


void insert_row(int index) {
    buffer.n_rows++;
    buffer.rows = realloc(buffer.rows, buffer.n_rows * sizeof(struct row));
    memmove(&buffer.rows[index + 1], &buffer.rows[index], (buffer.n_rows - index - 1) * sizeof(struct row));
    init_row(&buffer.rows[index]);
}

void concat_row(struct row *dest, struct row *src) {
    dest->size += src->size;
    dest->data = realloc(dest->data, dest->size);
    memcpy(&dest->data[dest->size - src->size], src->data, src->size);
}

void remove_row(int index) {
    buffer.n_rows--;
    memmove(&buffer.rows[index], &buffer.rows[index + 1], buffer.n_rows - index);
}

/* Printing */

void write_char(char c) {
    if (write(STDOUT_FILENO, &c, 1) != 1) die("write_char");
}

void write_string(const char *string) {
    if (write(STDOUT_FILENO, string, strlen(string)) != strlen(string)) die("write_string");
}

void write_row(struct row *row) {
    if (write(STDOUT_FILENO, row->data, row->size) != row->size) die("write_row");
}

void write_buffer() {
    for (int i = 0; i < buffer.n_rows; i++) {
        write_row(&buffer.rows[i]);
        write_string("\r\n");
    }
}

void clear_screen() {
    write_string("\x1b[2J");
    write_string("\x1b[1;1H");
}

/* Terminal manipulation */

void set_row(int row) {
    write_string("\x1b[");
    int length = snprintf(NULL, 0, "%d", row) + 1;
    char number[length];
    snprintf(number, length, "%d", row);
    write_string(number);
    write_string("H");
}

void set_column(int column) {
    write_string("\x1b[");
    int length = snprintf(NULL, 0, "%d", column) + 1;
    char number[length];
    snprintf(number, length, "%d", column);
    write_string(number);
    write_string("G");
}

/* Processing */

char read_key_press() {
    int chars_read;
    char c;

    while ((chars_read = read(STDIN_FILENO, &c, 1)) != 1) {
        if (chars_read == -1) die("read");
    }

    return c;
}

void handle_key_press() {
    char c = read_key_press();

    if (c == CTRL_PLUS('q')) {
        clear_screen();
        write_buffer();
        exit(EXIT_FAILURE);
    } else if (c == KEY_ENTER) {
        insert_row(buffer.cy + 1);
        buffer.rows[buffer.cy + 1].size = buffer.rows[buffer.cy].size - buffer.cx;
        memcpy(buffer.rows[buffer.cy + 1].data, &buffer.rows[buffer.cy].data[buffer.cx], buffer.rows[buffer.cy + 1].size);
        buffer.rows[buffer.cy].size = buffer.cx;

        write_string("\x1b[0J");

        for (int i = buffer.cy + 1; i < buffer.n_rows; i++) {
            write_string("\r\n");
            write_row(&buffer.rows[i]);
        }

        buffer.cx = 0;
        buffer.cy++;

        set_row(buffer.cy + 1);
        set_column(buffer.cx + 1);
    } else if (c == KEY_BACKSPACE) {
        if (buffer.cx == 0 && buffer.cy == 0) return;
        if (buffer.cx == 0) {
            concat_row(&buffer.rows[buffer.cy-1], &buffer.rows[buffer.cy]);
            remove_row(buffer.cy);
            buffer.cy--;
            buffer.cx = buffer.rows[buffer.cy].size;

            write_string("\x1b[1F");
            write_string("\x1b[0K");
            write_string(buffer.rows[buffer.cy].data);
            write_string("\x1b[0J");

            for (int i = buffer.cy + 2; i < buffer.n_rows; i++) {
                write_string("\r\n");
                write_row(&buffer.rows[i]);
            }

            set_row(buffer.cy + 1);
            set_column(buffer.cx + 1);
        } else {
            remove_char(&buffer.rows[buffer.cy], buffer.cx);
            buffer.cx--;

            write_string("\b");
            write_string("\x1b[0K");
            write(STDOUT_FILENO, &buffer.rows[buffer.cy] + buffer.cx, buffer.rows[buffer.cy].size - buffer.cx);
        }
    } else if (c == '\x1b') {
        if (read_key_press() == '[') {
            char arrow = read_key_press();
            if (arrow == 'D') {                 // Left
                if (buffer.cx > 0) {
                    buffer.cx--;
                    write_string("\x1b[D");
                }
            } else if (arrow == 'C') {          // Right
                if (buffer.cx < buffer.rows[buffer.cy].size) {
                    buffer.cx++;
                    write_string("\x1b[C");
                }
            } else if (arrow == 'A') {          // Up
                if (buffer.cy > 0) {
                    buffer.cy--;
                    write_string("\x1b[A");
                }
            } else if (arrow == 'B') {          // Down
                if (buffer.cy < buffer.n_rows - 1) {
                    buffer.cy++;
                    write_string("\x1b[B");

                    if (buffer.cx >= buffer.rows[buffer.cy].size) {
                        buffer.cx = buffer.rows[buffer.cy].size - 1;
                    }
                }
            }
        }
    } else if (isprint(c)) {
        write_char(c);

        insert_char(&buffer.rows[buffer.cy], buffer.cx, c);
        buffer.cx++;
    }
}

/* Main */

int main() {
    enable_raw_mode();
    clear_screen();

    init_buffer();

    while(1) {
        handle_key_press();
    }

    return 0;
}
