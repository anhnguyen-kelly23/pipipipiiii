#include <stdint.h>

void *memcpy(void *d, const void *s, unsigned int n) {
    uint8_t *dd = (uint8_t*)d;
    const uint8_t *ss = (const uint8_t*)s;
    while (n--) *dd++ = *ss++;
    return d;
}
void *memset(void *d, int c, unsigned int n) {
    uint8_t *dd = (uint8_t*)d; while (n--) *dd++ = (uint8_t)c; return d;
}

#define OUTBYTE  (*(volatile uint32_t*)0x10000000)
#define UART_TX  (*(volatile uint32_t*)0x10000004)
#define UART_ST  (*(volatile uint32_t*)0x1000000C)

/* TinyJAMBU (base 0x3000_0000) */
#define JB(off)    (*(volatile uint32_t*)(0x30000000+(off)))
#define JB_CTRL    JB(0x44)
#define JB_STATUS  JB(0x48)

/* Xoodyak (base 0x4000_0000) */
#define XD(off)    (*(volatile uint32_t*)(0x40000000+(off)))
#define XD_CTRL    XD(0x50)
#define XD_STATUS  XD(0x54)

/* GIFT-COFB (base 0x5000_0000) */
#define GC(off)    (*(volatile uint32_t*)(0x50000000+(off)))
#define GC_CTRL    GC(0x50)
#define GC_STATUS  GC(0x54)
#define GC_ACK     GC(0x78)

/* ---- UART ---- */
void pc(char c) {
    if (c == '\n') { while (!(UART_ST & 1)); UART_TX = '\r'; }
    while (!(UART_ST & 1));
    UART_TX = c;
}
void ps(const char *s) { while (*s) pc(*s++); }
void ph(uint32_t v) {
    const char h[] = "0123456789abcdef";
    for (int i = 28; i >= 0; i -= 4) pc(h[(v >> i) & 0xF]);
}
void p128(const uint32_t w[4]) { ph(w[3]); ph(w[2]); ph(w[1]); ph(w[0]); }
void p96(const uint32_t w[3])  { ph(w[2]); ph(w[1]); ph(w[0]); }
void p64(const uint32_t w[2])  { ph(w[1]); ph(w[0]); }
void ln(void) { ps("# ----------------------------------------\n"); }

/* ====================================================
 * CORE 1: TinyJAMBU - All 4 KAT test vectors + tampered tag
 * ==================================================== */

/* Helper: run one TinyJAMBU encrypt+decrypt test case, return 1 if both pass */
static int jb_test(const char *label,
                   const uint32_t key[4], const uint32_t nonce[3],
                   const uint32_t ad[4],  uint32_t adlen,
                   const uint32_t pt[4],  const uint32_t exp_ct[4],
                   uint32_t mlen, const uint32_t exp_tag[2])
{
    uint32_t ct[4], tag[2], dec[4];

    ps("# -- "); ps(label); ps(" --\n");
    ps("# key:       "); p128(key);   pc('\n');
    ps("# nonce:     "); p96(nonce);  pc('\n');
    ps("# ad:        "); p128(ad);    pc('\n');
    ps("# plaintext: "); p128(pt);    pc('\n');
    ln();

    /* Encrypt */
    JB(0x00)=key[0]; JB(0x04)=key[1]; JB(0x08)=key[2]; JB(0x0C)=key[3];
    JB(0x10)=nonce[0]; JB(0x14)=nonce[1]; JB(0x18)=nonce[2];
    JB(0x1C)=ad[0]; JB(0x20)=ad[1]; JB(0x24)=ad[2]; JB(0x28)=ad[3];
    JB(0x2C)=pt[0]; JB(0x30)=pt[1]; JB(0x34)=pt[2]; JB(0x38)=pt[3];
    JB_CTRL = (1u<<16) | (adlen<<8) | mlen;
    while (!(JB_STATUS & 0x02));

    ct[0]=JB(0x4C); ct[1]=JB(0x50); ct[2]=JB(0x54); ct[3]=JB(0x58);
    tag[0]=JB(0x5C); tag[1]=JB(0x60);
    ps("# ciphertext: "); p128(ct);  pc('\n');
    ps("# tag:        "); p64(tag);  pc('\n');

    int enc_ok = (ct[0]==exp_ct[0])&&(ct[1]==exp_ct[1])&&
                 (ct[2]==exp_ct[2])&&(ct[3]==exp_ct[3])&&
                 (tag[0]==exp_tag[0])&&(tag[1]==exp_tag[1]);
    ps("#   ENCRYPT: "); ps(enc_ok?"PASS":"FAIL"); pc('\n');
    ln();

    /* Decrypt */
    JB(0x00)=key[0]; JB(0x04)=key[1]; JB(0x08)=key[2]; JB(0x0C)=key[3];
    JB(0x10)=nonce[0]; JB(0x14)=nonce[1]; JB(0x18)=nonce[2];
    JB(0x1C)=ad[0]; JB(0x20)=ad[1]; JB(0x24)=ad[2]; JB(0x28)=ad[3];
    JB(0x2C)=ct[0]; JB(0x30)=ct[1]; JB(0x34)=ct[2]; JB(0x38)=ct[3];
    JB(0x3C)=tag[0]; JB(0x40)=tag[1];
    JB_CTRL = (2u<<16) | (adlen<<8) | mlen;
    while (!(JB_STATUS & 0x02));

    dec[0]=JB(0x4C); dec[1]=JB(0x50); dec[2]=JB(0x54); dec[3]=JB(0x58);
    int valid = (JB_STATUS & 0x01) ? 1 : 0;
    ps("# plaintext: "); p128(dec); pc('\n');
    ps("# valid:     "); pc('0'+valid); pc('\n');
    int dec_ok = valid&&(dec[0]==pt[0])&&(dec[1]==pt[1])&&
                        (dec[2]==pt[2])&&(dec[3]==pt[3]);
    ps("#   DECRYPT: "); ps(dec_ok?"PASS":"FAIL"); pc('\n');
    ln();

    return enc_ok && dec_ok;
}

void test_tinyjambu(int *pass)
{
    int ok1, ok2, ok3, ok4, ok5;

    ps("# [CORE 1] TinyJAMBU AEAD (4 test vectors)\n");
    ln();

    /* -- TC1: adlen=12, mlen=12 ----------------------------------------- */
    {
        uint32_t key[4]     = {0x628D2DDB, 0x405D3CCD, 0xC88A9CDD, 0x899CD0F7};
        uint32_t nonce[3]   = {0xD7F6659B, 0x89158AF8, 0x535E438A};
        uint32_t ad[4]      = {0xF1C8D2B4, 0xF0AC0C0E, 0x49A44D0E, 0x00000000};
        uint32_t pt[4]      = {0x3CDB944B, 0x89F0E435, 0x3BF1A7D2, 0x00000000};
        uint32_t exp_ct[4]  = {0xF04D0F20, 0xF3BEB3F2, 0x73C2C23A, 0x00000000};
        uint32_t exp_tag[2] = {0x1DEC6827, 0xE0D0722E};
        ok1 = jb_test("TC1: ad=12B msg=12B", key, nonce, ad, 12, pt, exp_ct, 12, exp_tag);
    }

    /* -- TC2: adlen=16, mlen=16 ----------------------------------------- */
    {
        uint32_t key[4]     = {0x6b9df1b7, 0xb8b647dd, 0xa0bf5446, 0x2bbf8981};
        uint32_t nonce[3]   = {0x47b2fa5d, 0xf8b84c8e, 0x62ab30be};
        uint32_t ad[4]      = {0x150bba1e, 0x6549facd, 0x95d38ce0, 0xf37a89f6};
        uint32_t pt[4]      = {0xc8325fec, 0x14ab5fe6, 0x2a73580e, 0x40c8d8f2};
        uint32_t exp_ct[4]  = {0x3ebd5a89, 0x55e3d4f3, 0x3a77204b, 0x3730c94a};
        uint32_t exp_tag[2] = {0x6ebdafd0, 0xfa0fe4e7};
        ok2 = jb_test("TC2: ad=16B msg=16B", key, nonce, ad, 16, pt, exp_ct, 16, exp_tag);
    }

    /* -- TC3: adlen=10, mlen=3 ------------------------------------------ */
    {
        uint32_t key[4]     = {0x0C0D0E0F, 0x08090A0B, 0x04050607, 0x00010203};
        uint32_t nonce[3]   = {0x08090A0B, 0x04050607, 0x00010203};
        uint32_t ad[4]      = {0x06070809, 0x02030405, 0x00000001, 0x00000000};
        uint32_t pt[4]      = {0x00000102, 0x00000000, 0x00000000, 0x00000000};
        uint32_t exp_ct[4]  = {0x0002D9F6, 0x00000000, 0x00000000, 0x00000000};
        uint32_t exp_tag[2] = {0x51B453CD, 0x67431DBB};
        ok3 = jb_test("TC3: ad=10B msg=3B", key, nonce, ad, 10, pt, exp_ct, 3, exp_tag);
    }

    /* -- TC4: adlen=15, mlen=8 ------------------------------------------ */
    {
        uint32_t key[4]     = {0x0C0D0E0F, 0x08090A0B, 0x04050607, 0x00010203};
        uint32_t nonce[3]   = {0x08090A0B, 0x04050607, 0x00010203};
        uint32_t ad[4]      = {0x0B0C0D0E, 0x0708090A, 0x03040506, 0x00000102};
        uint32_t pt[4]      = {0x04050607, 0x00010203, 0x00000000, 0x00000000};
        uint32_t exp_ct[4]  = {0x82CD4009, 0xF890838D, 0x00000000, 0x00000000};
        uint32_t exp_tag[2] = {0xF991CD3A, 0x371A52DE};
        ok4 = jb_test("TC4: ad=15B msg=8B", key, nonce, ad, 15, pt, exp_ct, 8, exp_tag);
    }

    /* -- TC5: Tampered tag -> must REJECT -------------------------------- */
    {
        uint32_t key[4]     = {0x628D2DDB, 0x405D3CCD, 0xC88A9CDD, 0x899CD0F7};
        uint32_t nonce[3]   = {0xD7F6659B, 0x89158AF8, 0x535E438A};
        uint32_t ad[4]      = {0xF1C8D2B4, 0xF0AC0C0E, 0x49A44D0E, 0x00000000};
        uint32_t ct[4]      = {0xF04D0F20, 0xF3BEB3F2, 0x73C2C23A, 0x00000000};
        uint32_t bad_tag[2] = {0x1DEC6827 ^ 0xCAFEBABE, 0xE0D0722E ^ 0xDEADBEEF};

        ps("# -- TC5: tampered tag (expect REJECT) --\n");
        JB(0x00)=key[0]; JB(0x04)=key[1]; JB(0x08)=key[2]; JB(0x0C)=key[3];
        JB(0x10)=nonce[0]; JB(0x14)=nonce[1]; JB(0x18)=nonce[2];
        JB(0x1C)=ad[0]; JB(0x20)=ad[1]; JB(0x24)=ad[2]; JB(0x28)=ad[3];
        JB(0x2C)=ct[0]; JB(0x30)=ct[1]; JB(0x34)=ct[2]; JB(0x38)=ct[3];
        JB(0x3C)=bad_tag[0]; JB(0x40)=bad_tag[1];
        JB_CTRL = (2u<<16) | (12u<<8) | 12u;
        while (!(JB_STATUS & 0x02));
        int valid = (JB_STATUS & 0x01) ? 1 : 0;
        ok5 = !valid;  /* pass if correctly rejected */
        ps("#   REJECT: "); ps(ok5?"PASS":"FAIL"); pc('\n');
    }

    ln();
    *pass = ok1 && ok2 && ok3 && ok4 && ok5;
    ps(*pass ? "# TinyJAMBU: ALL 5 TESTS PASS\n" : "# TinyJAMBU: FAILED\n");
    ln();
}

/* ====================================================
 * CORE 2: Xoodyak (Custom - 9B AD, 14B PT, KAT verified)
 * ==================================================== */
void test_xoodyak(int *pass)
{
    uint32_t key[4]     = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
    uint32_t nonce[4]   = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};
    uint32_t ad[4]      = {0x00000000, 0x08000000, 0x04050607, 0x00010203};
    uint32_t pt[4]      = {0x0c0d0e00, 0x08090a0b, 0x04050607, 0x00010203};
    uint32_t exp_ct[4]  = {0x93090000, 0x6b339d70, 0x24fb2cc1, 0x76e90670};
    uint32_t exp_tag[4] = {0x25016e36, 0x0dc1f1c9, 0x717ed777, 0x572a92e7};
    uint32_t ct[4], tag[4], dec[4];

    ps("# [CORE 2] Xoodyak AEAD (9B AD, 14B PT)\n");
    ln();
    ps("# key:       "); p128(key);   pc('\n');  ps("# nonce: "); p128(nonce); pc('\n');
    ps("# ad:        "); p128(ad);    pc('\n');
    ps("# plaintext: "); p128(pt);    pc('\n');
    ln();

    /* Encrypt */
    OUTBYTE = 0x30;
    XD(0x00)=key[0]; XD(0x04)=key[1]; XD(0x08)=key[2]; XD(0x0C)=key[3];
    XD(0x10)=nonce[0]; XD(0x14)=nonce[1]; XD(0x18)=nonce[2]; XD(0x1C)=nonce[3];
    XD(0x20)=ad[0]; XD(0x24)=ad[1]; XD(0x28)=ad[2]; XD(0x2C)=ad[3];
    XD(0x30)=pt[0]; XD(0x34)=pt[1]; XD(0x38)=pt[2]; XD(0x3C)=pt[3];
    XD(0x40)=0; XD(0x44)=0; XD(0x48)=0; XD(0x4C)=0;
    XD_CTRL = (1u<<16) | (9u<<8) | 14u;
    while (!(XD_STATUS & 0x02));

    ct[0]=XD(0x58); ct[1]=XD(0x5C); ct[2]=XD(0x60); ct[3]=XD(0x64);
    tag[0]=XD(0x68); tag[1]=XD(0x6C); tag[2]=XD(0x70); tag[3]=XD(0x74);
    ps("# ciphertext: "); p128(ct);  pc('\n');
    ps("# tag:        "); p128(tag); pc('\n');

    int ct_ok = (ct[3]==exp_ct[3])&&(ct[2]==exp_ct[2])&&(ct[1]==exp_ct[1])&&
                ((ct[0]&0xFFFF0000)==(exp_ct[0]&0xFFFF0000));
    int tag_ok = (tag[0]==exp_tag[0])&&(tag[1]==exp_tag[1])&&
                 (tag[2]==exp_tag[2])&&(tag[3]==exp_tag[3]);
    ps("#   ENCRYPT: "); ps((ct_ok&&tag_ok)?"PASS":"FAIL"); pc('\n');
    ln();

    /* Decrypt */
    OUTBYTE = 0x70;
    XD(0x00)=key[0]; XD(0x04)=key[1]; XD(0x08)=key[2]; XD(0x0C)=key[3];
    XD(0x10)=nonce[0]; XD(0x14)=nonce[1]; XD(0x18)=nonce[2]; XD(0x1C)=nonce[3];
    XD(0x20)=ad[0]; XD(0x24)=ad[1]; XD(0x28)=ad[2]; XD(0x2C)=ad[3];
    XD(0x30)=ct[0]; XD(0x34)=ct[1]; XD(0x38)=ct[2]; XD(0x3C)=ct[3];
    XD(0x40)=tag[0]; XD(0x44)=tag[1]; XD(0x48)=tag[2]; XD(0x4C)=tag[3];
    XD_CTRL = (2u<<16) | (9u<<8) | 14u;
    while (!(XD_STATUS & 0x02));

    dec[0]=XD(0x58); dec[1]=XD(0x5C); dec[2]=XD(0x60); dec[3]=XD(0x64);
    int valid = (XD_STATUS & 0x01) ? 1 : 0;
    ps("# plaintext: "); p128(dec); pc('\n');
    ps("# valid: "); pc('0'+valid); pc('\n');
    int pt_ok = (dec[3]==pt[3])&&(dec[2]==pt[2])&&(dec[1]==pt[1])&&
                ((dec[0]&0xFFFF0000)==(pt[0]&0xFFFF0000));
    ps("#   DECRYPT: "); ps((valid&&pt_ok)?"PASS":"FAIL"); pc('\n');
    ln();

    *pass = ct_ok && tag_ok && valid && pt_ok;
    ps(*pass ? "# Xoodyak: ALL PASS\n" : "# Xoodyak: FAILED\n");
    ln();
}

/* ====================================================
 * CORE 3: GIFT-COFB
 *
 * Test A: Single-block (KAT #533)
 *   AD=4B, PT=16B
 *
 * Test B: Multi-block (KAT #579)
 *   AD=17B (2 blocks), PT=17B (2 blocks)
 *   Exercises req/ack handshaking
 *
 * STATUS register: [3]=ad_req [2]=msg_req [1]=done [0]=valid
 * ACK register (0x78): [1]=ad_ack [0]=msg_ack
 * ==================================================== */

/* Helpers */
static void gc_set_key_nonce(void) {
    /* Key = Nonce = 000102030405060708090A0B0C0D0E0F */
    GC(0x00)=0x0c0d0e0f; GC(0x04)=0x08090a0b;
    GC(0x08)=0x04050607; GC(0x0C)=0x00010203;
    GC(0x10)=0x0c0d0e0f; GC(0x14)=0x08090a0b;
    GC(0x18)=0x04050607; GC(0x1C)=0x00010203;
}
static void gc_set_ad(uint32_t w3, uint32_t w2, uint32_t w1, uint32_t w0) {
    GC(0x20)=w0; GC(0x24)=w1; GC(0x28)=w2; GC(0x2C)=w3;
}
static void gc_set_msg(uint32_t w3, uint32_t w2, uint32_t w1, uint32_t w0) {
    GC(0x30)=w0; GC(0x34)=w1; GC(0x38)=w2; GC(0x3C)=w3;
}
static void gc_set_tag(uint32_t w3, uint32_t w2, uint32_t w1, uint32_t w0) {
    GC(0x40)=w0; GC(0x44)=w1; GC(0x48)=w2; GC(0x4C)=w3;
}

void test_giftcofb(int *pass)
{
    uint32_t ct[4], tag[4], dec[4];
    int testA_ok = 0, testB_ok = 0;

    ps("# [CORE 3] GIFT-COFB AEAD\n");
    ln();
    ps("# key:   "); p128((uint32_t[]){0x0c0d0e0f,0x08090a0b,0x04050607,0x00010203}); pc('\n');
    ps("# nonce: "); p128((uint32_t[]){0x0c0d0e0f,0x08090a0b,0x04050607,0x00010203}); pc('\n');
    ln();

    /* ====================================================
     * Test A: Single-block (KAT #533)
     *   AD  = 00010203 (4 bytes)       PT = 000102..0F (16 bytes)
     *   CT  = ACA0E4DAF3CEAEBB2AD9211FF6CC70D
     *   Tag = 51859C4EBBBD8B170CC8BAE67490194C
     * ==================================================== */
    {
        uint32_t exp_ct[4]  = {0xFF6CC70D, 0xE2AD9211, 0xF3CEAEBB, 0xACA0E4DA};
        uint32_t exp_tag[4] = {0x7490194C, 0x0CC8BAE6, 0xBBBD8B17, 0x51859C4E};
        uint32_t pt[4]      = {0x0c0d0e0f, 0x08090a0b, 0x04050607, 0x00010203};

        ps("# -- Test A: single-block (KAT #533) --\n");
        ps("# ad(4B):  00010203\n");
        ps("# plaintext(16B): "); p128(pt); pc('\n');

        /* Encrypt */
        gc_set_key_nonce();
        gc_set_ad(0x00010203, 0x00000000, 0x00000000, 0x00000000);
        gc_set_msg(0x00010203, 0x04050607, 0x08090a0b, 0x0c0d0e0f);
        gc_set_tag(0,0,0,0);
        GC_CTRL = (0u<<16) | (4u<<8) | 16u;
        while (!(GC_STATUS & 0x02));

        ct[0]=GC(0x58); ct[1]=GC(0x5C); ct[2]=GC(0x60); ct[3]=GC(0x64);
        tag[0]=GC(0x68); tag[1]=GC(0x6C); tag[2]=GC(0x70); tag[3]=GC(0x74);
        ps("# ciphertext: "); p128(ct);  pc('\n');
        ps("# tag:        "); p128(tag); pc('\n');

        int enc_ok = (ct[0]==exp_ct[0])&&(ct[1]==exp_ct[1])&&
                     (ct[2]==exp_ct[2])&&(ct[3]==exp_ct[3])&&
                     (tag[0]==exp_tag[0])&&(tag[1]==exp_tag[1])&&
                     (tag[2]==exp_tag[2])&&(tag[3]==exp_tag[3]);
        ps("#   ENCRYPT: "); ps(enc_ok?"PASS":"FAIL"); pc('\n');

        /* Decrypt */
        gc_set_key_nonce();
        gc_set_ad(0x00010203, 0x00000000, 0x00000000, 0x00000000);
        gc_set_msg(exp_ct[3], exp_ct[2], exp_ct[1], exp_ct[0]);
        gc_set_tag(exp_tag[3], exp_tag[2], exp_tag[1], exp_tag[0]);
        GC_CTRL = (1u<<16) | (4u<<8) | 16u;
        while (!(GC_STATUS & 0x02));

        dec[0]=GC(0x58); dec[1]=GC(0x5C); dec[2]=GC(0x60); dec[3]=GC(0x64);
        int valid = (GC_STATUS & 0x01) ? 1 : 0;
        ps("# plaintext: "); p128(dec); pc('\n');
        ps("# valid: "); pc('0'+valid); pc('\n');
        int dec_ok = valid&&(dec[0]==pt[0])&&(dec[1]==pt[1])&&
                            (dec[2]==pt[2])&&(dec[3]==pt[3]);
        ps("#   DECRYPT: "); ps(dec_ok?"PASS":"FAIL"); pc('\n');

        testA_ok = enc_ok && dec_ok;
        ps("#   Test A: "); ps(testA_ok?"PASS":"FAIL"); pc('\n');
        ln();
    }

    /* ====================================================
     * Test B: Multi-block (KAT #579)
     *   AD  = 000102030405060708090A0B0C0D0E0F 10  (17 bytes, 2 blocks)
     *   PT  = 000102030405060708090A0B0C0D0E0F 10  (17 bytes, 2 blocks)
     *   CT  = 54B63042B7680D22824EFFE3DA23161C 2D  (17 bytes)
     *   Tag = 82C5C511B0433543A0DA30559C079228
     *
     *   Flow:
     *     1. Write AD block 0, MSG block 0, start
     *     2. Poll: ad_req  -> write AD block 1, ack
     *     3. Poll: msg_req -> read CT block 0, write MSG block 1, ack
     *     4. Poll: done    -> read CT block 1 + tag
     * ==================================================== */
    {
        /* block 0 for AD and MSG (same data) */
        /* 000102030405060708090A0B0C0D0E0F */
        uint32_t blk0_w3=0x00010203, blk0_w2=0x04050607;
        uint32_t blk0_w1=0x08090a0b, blk0_w0=0x0c0d0e0f;
        /* block 1: byte 0x10 MSB-aligned */
        uint32_t blk1_w3=0x10000000, blk1_w2=0, blk1_w1=0, blk1_w0=0;

        uint32_t exp_ct0[4] = {0xDA23161C, 0x824EFFE3, 0xB7680D22, 0x54B63042};
        uint32_t exp_tag[4] = {0x9C079228, 0xA0DA3055, 0xB0433543, 0x82C5C511};
        uint32_t ct0[4];
        uint32_t pt0[4] = {blk0_w0, blk0_w1, blk0_w2, blk0_w3};

        ps("# -- Test B: multi-block (KAT 579) --\n");
        ps("# ad(17B):  000102030405060708090A0B0C0D0E0F 10\n");
        ps("# msg(17B): 000102030405060708090A0B0C0D0E0F 10\n");

        /* ---- ENCRYPT ---- */
        gc_set_key_nonce();
        gc_set_ad(blk0_w3, blk0_w2, blk0_w1, blk0_w0);
        gc_set_msg(blk0_w3, blk0_w2, blk0_w1, blk0_w0);
        gc_set_tag(0,0,0,0);
        GC_CTRL = (0u<<16) | (17u<<8) | 17u;

        /* Serve AD and MSG blocks via req/ack */
        while (1) {
            uint32_t st = GC_STATUS;
            if (st & 0x08) {
                /* ad_req: write AD block 1 */
                gc_set_ad(blk1_w3, blk1_w2, blk1_w1, blk1_w0);
                GC_ACK = 0x02;
            } else if (st & 0x04) {
                /* msg_req: save CT block 0, write MSG block 1 */
                ct0[0]=GC(0x58); ct0[1]=GC(0x5C);
                ct0[2]=GC(0x60); ct0[3]=GC(0x64);
                gc_set_msg(blk1_w3, blk1_w2, blk1_w1, blk1_w0);
                GC_ACK = 0x01;
            } else if (st & 0x02) {
                /* done: read last CT block + tag */
                uint32_t ct1[4];
                ct1[0]=GC(0x58); ct1[1]=GC(0x5C);
                ct1[2]=GC(0x60); ct1[3]=GC(0x64);
                tag[0]=GC(0x68); tag[1]=GC(0x6C);
                tag[2]=GC(0x70); tag[3]=GC(0x74);

                ps("# CT blk0: "); p128(ct0);  pc('\n');
                ps("# CT blk1: "); ph(ct1[3]); pc('\n');
                ps("# Tag:     "); p128(tag);  pc('\n');

                int ct0_ok = (ct0[0]==exp_ct0[0])&&(ct0[1]==exp_ct0[1])&&
                             (ct0[2]==exp_ct0[2])&&(ct0[3]==exp_ct0[3]);
                int ct1_ok = ((ct1[3]>>24)==0x2D);  /* only 1 byte valid */
                int tag_ok = (tag[0]==exp_tag[0])&&(tag[1]==exp_tag[1])&&
                             (tag[2]==exp_tag[2])&&(tag[3]==exp_tag[3]);
                int enc_ok = ct0_ok && ct1_ok && tag_ok;
                ps("#   ENCRYPT: "); ps(enc_ok?"PASS":"FAIL"); pc('\n');

                /* ---- DECRYPT ---- */
                gc_set_key_nonce();
                gc_set_ad(blk0_w3, blk0_w2, blk0_w1, blk0_w0);
                /* Feed CT block 0 as msg_data */
                gc_set_msg(ct0[3], ct0[2], ct0[1], ct0[0]);
                gc_set_tag(exp_tag[3], exp_tag[2], exp_tag[1], exp_tag[0]);
                GC_CTRL = (1u<<16) | (17u<<8) | 17u;

                uint32_t dec0[4], dec1[4];
                while (1) {
                    uint32_t st = GC_STATUS;
                    if (st & 0x08) {
                        /* ad_req: write AD block 1 */
                        gc_set_ad(blk1_w3, blk1_w2, blk1_w1, blk1_w0);
                        GC_ACK = 0x02;
                    } else if (st & 0x04) {
                        /* msg_req: save PT block 0, feed CT block 1 */
                        dec0[0]=GC(0x58); dec0[1]=GC(0x5C);
                        dec0[2]=GC(0x60); dec0[3]=GC(0x64);
                        gc_set_msg(ct1[3], ct1[2], ct1[1], ct1[0]);
                        GC_ACK = 0x01;
                    } else if (st & 0x02) {
                        dec1[0]=GC(0x58); dec1[1]=GC(0x5C);
                        dec1[2]=GC(0x60); dec1[3]=GC(0x64);
                        break;
                    }
                }
                int valid = (GC_STATUS & 0x01) ? 1 : 0;
                ps("# PT blk0: "); p128(dec0); pc('\n');
                ps("# PT blk1: "); ph(dec1[3]); pc('\n');
                ps("# valid:   "); pc('0'+valid); pc('\n');
                int pt0_ok = (dec0[0]==pt0[0])&&(dec0[1]==pt0[1])&&
                             (dec0[2]==pt0[2])&&(dec0[3]==pt0[3]);
                int pt1_ok = ((dec1[3]>>24)==0x10);  /* 1 byte */
                int dec_ok = valid && pt0_ok && pt1_ok;
                ps("#   DECRYPT: "); ps(dec_ok?"PASS":"FAIL"); pc('\n');

                testB_ok = enc_ok && dec_ok;
                ps("#   Test B: "); ps(testB_ok?"PASS":"FAIL"); pc('\n');
                ln();
                break;
            }
        }
    }

    *pass = testA_ok && testB_ok;
    ps(*pass ? "# GIFT-COFB: ALL PASS\n" : "# GIFT-COFB: FAILED\n");
    ln();
}

/* ====================================================
 * SD Card over SPI (raw sector read demo)
 * Memory map:
 *   0x6000_0000 DATA    [7:0] tx/rx
 *   0x6000_0004 STATUS  [2]=cs_n [1]=busy [0]=done
 *   0x6000_0008 CTRL    [0]=cs_n
 *   0x6000_000C CLKDIV  [15:0] half-period divider
 * ==================================================== */
#define SDSPI(off)      (*(volatile uint32_t*)(0x60000000u + (off)))
#define SDSPI_DATA      SDSPI(0x00)
#define SDSPI_STATUS    SDSPI(0x04)
#define SDSPI_CTRL      SDSPI(0x08)
#define SDSPI_CLKDIV    SDSPI(0x0C)

#define SDSPI_ST_DONE   0x01
#define SDSPI_ST_BUSY   0x02

static int sd_is_sdhc = 0;
static uint8_t sd_sector0[512];

static void ph8(uint8_t v) {
    const char h[] = "0123456789abcdef";
    pc(h[(v >> 4) & 0xF]);
    pc(h[v & 0xF]);
}

static void dump_bytes(const uint8_t *buf, int count)
{
    for (int i = 0; i < count; i++) {
        if ((i & 15) == 0) {
            pc('\n');
            ps("#   ");
        }
        ph8(buf[i]);
        pc(' ');
    }
    pc('\n');
}

static void sd_spi_set_div(uint16_t div)
{
    SDSPI_CLKDIV = div;
}

static void sd_spi_cs(int high)
{
    SDSPI_CTRL = high ? 1u : 0u;
}

static uint8_t sd_spi_xfer(uint8_t tx)
{
    while (SDSPI_STATUS & SDSPI_ST_BUSY);
    SDSPI_DATA = tx;
    while (!(SDSPI_STATUS & SDSPI_ST_BUSY));
    while (SDSPI_STATUS & SDSPI_ST_BUSY);
    return (uint8_t)(SDSPI_DATA & 0xFF);
}

static int sd_wait_ready(uint32_t limit)
{
    while (limit--) {
        if (sd_spi_xfer(0xFF) == 0xFF)
            return 1;
    }
    return 0;
}

static void sd_deselect(void)
{
    sd_spi_cs(1);
    sd_spi_xfer(0xFF);
}

static int sd_select(void)
{
    sd_spi_cs(0);
    sd_spi_xfer(0xFF);
    return sd_wait_ready(50000);
}

static uint8_t sd_send_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
    uint8_t res;

    if (cmd & 0x80) {
        cmd &= 0x7F;
        res = sd_send_cmd(55, 0, 0x01);
        if (res > 1)
            return res;
    }

    sd_deselect();
    if (!sd_select())
        return 0xFF;

    sd_spi_xfer(0x40 | cmd);
    sd_spi_xfer((uint8_t)(arg >> 24));
    sd_spi_xfer((uint8_t)(arg >> 16));
    sd_spi_xfer((uint8_t)(arg >> 8));
    sd_spi_xfer((uint8_t)arg);
    sd_spi_xfer(crc);

    for (int i = 0; i < 10; i++) {
        res = sd_spi_xfer(0xFF);
        if ((res & 0x80) == 0)
            return res;
    }
    return 0xFF;
}

static int sd_init_card(void)
{
    uint8_t r;
    uint8_t ocr[4];

    sd_spi_set_div(199); /* 100 MHz / (2*(199+1)) = 250 kHz */
    sd_spi_cs(1);
    for (int i = 0; i < 10; i++)
        sd_spi_xfer(0xFF);

    r = sd_send_cmd(0, 0, 0x95);
    if (r != 0x01) {
        sd_deselect();
        return 0;
    }

    r = sd_send_cmd(8, 0x000001AAu, 0x87);
    if (r == 0x01) {
        for (int i = 0; i < 4; i++) {
            ocr[i] = sd_spi_xfer(0xFF);
            if (ocr[2] != 0x01 || ocr[3] != 0xAA) {
                sd_deselect();
                return 0;
            }
        }

        int ready = 0;
        for (uint32_t retry = 0; retry < 20000; retry++) {
            r = sd_send_cmd(0x80 | 41, 0x40000000u, 0x01);
            if (r == 0x00) {
                ready = 1;
                break;
            }
        }
        if (!ready) {
            sd_deselect();
            return 0;
        }

        if (sd_send_cmd(58, 0, 0x01) != 0x00) {
            sd_deselect();
            return 0;
        }
        for (int i = 0; i < 4; i++)
            ocr[i] = sd_spi_xfer(0xFF);
        sd_is_sdhc = (ocr[0] & 0x40) ? 1 : 0;
    } else {
        /* Older SDSC path */
        int ready = 0;
        for (uint32_t retry = 0; retry < 20000; retry++) {
            r = sd_send_cmd(0x80 | 41, 0x00000000u, 0x01);
            if (r == 0x00) {
                ready = 1;
                break;
            }
        }
        if (!ready) {
            sd_deselect();
            return 0;
        }
        if (sd_send_cmd(16, 512, 0x01) != 0x00) {
            sd_deselect();
            return 0;
        }
        sd_is_sdhc = 0;
    }

    sd_deselect();
    sd_spi_set_div(4); /* 100 MHz / (2*(4+1)) = 10 MHz */
    return 1;
}

static int sd_read_block(uint32_t lba, uint8_t *buf)
{
    uint32_t addr = sd_is_sdhc ? lba : (lba << 9);

    if (sd_send_cmd(17, addr, 0x01) != 0x00) {
        sd_deselect();
        return 0;
    }

    uint8_t token = 0xFF;
    for (uint32_t retry = 0; retry < 200000; retry++) {
        token = sd_spi_xfer(0xFF);
        if (token == 0xFE)
            break;
    }
    if (token != 0xFE) {
        sd_deselect();
        return 0;
    }

    for (int i = 0; i < 512; i++)
        buf[i] = sd_spi_xfer(0xFF);

    sd_spi_xfer(0xFF); /* CRC16[15:8] */
    sd_spi_xfer(0xFF); /* CRC16[7:0]  */
    sd_deselect();
    return 1;
}

static void test_sdcard(int *pass)
{
    ps("# [SD] SPI raw sector read\n");
    ln();

    if (!sd_init_card()) {
        ps("# SD init: FAIL\n");
        ln();
        *pass = 0;
        return;
    }

    ps("# SD init: PASS\n");
    ps("# Card type: ");
    ps(sd_is_sdhc ? "SDHC/SDXC\n" : "SDSC\n");

    if (!sd_read_block(0, sd_sector0)) {
        ps("# CMD17 sector 0: FAIL\n");
        ln();
        *pass = 0;
        return;
    }

    ps("# CMD17 sector 0: PASS\n");
    ps("# Sector0[510:511] signature: ");
    ph8(sd_sector0[510]); ph8(sd_sector0[511]); pc('\n');
    ps("# First 64 bytes of sector 0:");
    dump_bytes(sd_sector0, 64);

    *pass = (sd_sector0[510] == 0x55 && sd_sector0[511] == 0xAA);
    ps(*pass ? "# SD sector read: PASS\n" : "# SD sector read: WARN (no 0x55AA signature)\n");
    ln();
}

/* ====================================================
 * MAIN
 * ==================================================== */
void main(void)
{
    OUTBYTE = 0x01;
    for (volatile int i = 0; i < 500000; i++);

    int jb_pass=0, xd_pass=0, gc_pass=0, sd_pass=0;

    ps("\n\n");
    ps("# ======================================\n");
    ps("# PicoRV32 Crypto SoC + SD SPI\n");
    ps("# Core 1: TinyJAMBU  @ 0x3000_0000\n");
    ps("# Core 2: Xoodyak    @ 0x4000_0000\n");
    ps("# Core 3: GIFT-COFB  @ 0x5000_0000\n");
    ps("# SD SPI:            @ 0x6000_0000\n");
    ps("# Arty A7-100T  |  100 MHz\n");
    ps("# ======================================\n\n");

    test_tinyjambu(&jb_pass);
    ps("\n");
    test_xoodyak(&xd_pass);
    ps("\n");
    test_giftcofb(&gc_pass);
    ps("\n");
    test_sdcard(&sd_pass);

    ps("\n");
    ps("# ======================================\n");
    int all = jb_pass && xd_pass && gc_pass && sd_pass;
    if (all) {
        ps("# RESULT: ALL CRYPTO CORES + SD PASS\n");
        OUTBYTE = 0xFF;
    } else {
        ps("# RESULT: SOME TESTS FAILED\n");
        if (!jb_pass) ps("#   TinyJAMBU: FAIL\n");
        if (!xd_pass) ps("#   Xoodyak:   FAIL\n");
        if (!gc_pass) ps("#   GIFT-COFB: FAIL\n");
        if (!sd_pass) ps("#   SD SPI:    FAIL\n");
        OUTBYTE = 0x55;
    }
    ps("# ======================================\n");
    while (1);
}
