~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
// Prints the column names of one case.
int main(int argc, char** argv) {
    std::string c = argc > 1 ? argv[1] : "basic";
    std::cout << "id,name" << std::endl;
    return 0;
}
