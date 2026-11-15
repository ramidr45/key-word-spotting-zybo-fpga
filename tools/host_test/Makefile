# Compile la chaine DSP du firmware sur PC (gcc) pour la comparer a librosa.
SRC    = ../../sw/src
CFLAGS = -O2 -Wall -Wextra -std=c99 -I$(SRC)

all: kws_host main_check

kws_host: host_main.c $(SRC)/mfcc.c $(SRC)/mlp.c $(SRC)/resample.c
	$(CC) $(CFLAGS) -o $@ $^ -lm

# verifie que main.c (code carte) compile sans avertissement, avec des stubs Xilinx
main_check: $(SRC)/main.c
	$(CC) $(CFLAGS) -Istubs -fsyntax-only $<
	@echo "main.c : OK"

test: kws_host
	python3 compare.py

clean:
	rm -f kws_host *.f32
