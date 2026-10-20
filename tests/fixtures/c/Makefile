CFLAGS = -g -O0 -Wall -Wextra

build/shop: src/main.c src/discount.c src/discount.h | build
	$(CC) $(CFLAGS) -o $@ src/main.c src/discount.c

build:
	mkdir -p build

.PHONY: run clean
run: build/shop
	./build/shop

clean:
	rm -rf build
