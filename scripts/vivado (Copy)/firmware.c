#define UART_TX_DATA    (*(volatile int*)0x10000004)
#define UART_RX_DATA    (*(volatile int*)0x10000008)
#define UART_STATUS     (*(volatile int*)0x1000000C)
#define UART_BAUD_DIV   (*(volatile int*)0x10000010)
// Status bits
#define UART_TX_READY   (1 << 0)
#define UART_RX_VALID   (1 << 1)
// ============================================
// UART Helper Functions
// ============================================
void uart_wait_tx_ready()
{
	while (!(UART_STATUS & UART_TX_READY));
}
 
void uart_putc(char c)
{
	uart_wait_tx_ready();
	UART_TX_DATA = c;
}
 
void uart_puts(const char *s)
{
	while (*s) {
		uart_putc(*s);
		s++;
	}
}
 
void uart_println(const char *s)
{
	uart_puts(s);
	uart_putc('\r');
	uart_putc('\n');
}
 
char hex_digit(int val)
{
	val &= 0xF;
	return (val < 10) ? ('0' + val) : ('A' + val - 10);
}
 
void uart_print_hex8(int val)
{
	uart_putc(hex_digit(val >> 4));
	uart_putc(hex_digit(val));
}
 
void uart_print_dec(int val)
{
	if (val == 0) {
		uart_putc('0');
		return;
	}
 
	char buf[10];
	int i = 0;
 
	while (val > 0) {
		buf[i++] = '0' + (val % 10);
		val /= 10;
	}
 
	while (i > 0) {
		uart_putc(buf[--i]);
	}
}
 
// ============================================
// Legacy Functions
// ============================================
void putc(int c)
{
	*(volatile int*)0x10000000 = c;
}
 
void puts(const char *s)
{
	while (*s) putc(*s++);
}
 
void *memcpy(void *dest, const void *src, int n)
{
	while (n) {
		n--;
		((char*)dest)[n] = ((char*)src)[n];
	}
	return dest;
}
 
// ============================================
// Display Helper Functions
// ============================================
 
// In trang thai ON/OFF cho tung bit
void print_io_status(const char *prefix, int val, int num_bits, int led_offset)
{
	int i;
	for (i = 0; i < num_bits; i++) {
		uart_puts("  ");
		uart_puts(prefix);
		uart_print_dec(i);
 
		if (val & (1 << i)) {
			uart_puts(": ON  -> LD");
			uart_print_dec(i + led_offset);
			uart_puts(" sang");
		} else {
			uart_puts(": OFF");
		}
 
		uart_println("");
	}
}
 
void print_separator(void)
{
	uart_println("----------------------------------------");
}
 
// ============================================
// Main Program
// ============================================
void main()
{
	int sw_val, btn_val, led_val;
	int prev_sw_val = -1;
	int prev_btn_val = -1;
	int count = 0;
 
	uart_println("");
	uart_println("========================================");
	uart_println("  PicoRV32 on Arty A7-100T with UART");
	uart_println("========================================");
	uart_println("  SW0-SW3  -> LD0-LD3");
	uart_println("  BTN0-BTN3 -> LD4-LD7");
	uart_println("========================================");
	uart_println("");
 
	while (1)
	{
		// Doc switches va buttons
		sw_val  = *(volatile int*)0x20000000 & 0x0F;
		btn_val = *(volatile int*)0x20000004 & 0x0F;
 
		// LED output: SW -> LD0-LD3, BTN -> LD4-LD7
		led_val = sw_val | (btn_val << 4);
 
		// Chi in khi co thay doi
		if (sw_val != prev_sw_val || btn_val != prev_btn_val) {
 
			// Ghi ra LED
			*(volatile int*)0x10000000 = led_val;
 
			// Header
			uart_puts("[#");
			uart_print_dec(count++);
			uart_println("] Input changed:");
 
			// Hien thi trang thai Switch
			if (sw_val != prev_sw_val) {
				uart_puts("  Switch: ");
				if (sw_val == 0) {
					uart_println("tat het");
				} else {
					// Liet ke cac switch dang ON
					int first = 1;
					int i;
					for (i = 0; i < 4; i++) {
						if (sw_val & (1 << i)) {
							if (!first) uart_puts(", ");
							uart_puts("SW");
							uart_print_dec(i);
							first = 0;
						}
					}
					uart_println(" dang bat");
				}
			}
 
			// Hien thi trang thai Button
			if (btn_val != prev_btn_val) {
				uart_puts("  Button: ");
				if (btn_val == 0) {
					uart_println("khong nhan");
				} else {
					int first = 1;
					int i;
					for (i = 0; i < 4; i++) {
						if (btn_val & (1 << i)) {
							if (!first) uart_puts(", ");
							uart_puts("BTN");
							uart_print_dec(i);
							first = 0;
						}
					}
					uart_println(" dang nhan");
				}
			}
 
			// Hien thi LED
			uart_puts("  LED:    [");
			{
				int i;
				for (i = 7; i >= 0; i--) {
					if (led_val & (1 << i))
						uart_putc('*');
					else
						uart_putc('.');
				}
			}
			uart_puts("] LD7..LD0");
			uart_println("");
 
			// Liet ke LED sang
			uart_puts("          ");
			if (led_val == 0) {
				uart_puts("tat het");
			} else {
				int first = 1;
				int i;
				for (i = 0; i < 8; i++) {
					if (led_val & (1 << i)) {
						if (!first) uart_puts(", ");
						uart_puts("LD");
						uart_print_dec(i);
						first = 0;
					}
				}
				uart_puts(" sang");
			}
			uart_println("");
 
			print_separator();
 
			prev_sw_val = sw_val;
			prev_btn_val = btn_val;
		}
 
		// UART RX echo
		if (UART_STATUS & UART_RX_VALID) {
			char received = UART_RX_DATA & 0xFF;
 
			uart_puts("UART RX: '");
			uart_putc(received);
			uart_puts("' (0x");
			uart_print_hex8(received);
			uart_println(")");
		}
	}
}
