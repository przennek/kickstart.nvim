#include "discount.h"

double final_price(double total, int items, int min_items) {
    if (items >= min_items) {
        return total * 0.9;
    }
    return total;
}
