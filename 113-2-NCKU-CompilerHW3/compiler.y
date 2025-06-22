
/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h" //Extern variables that communicate with lex
    // #define YYDEBUG 1
    // int yydebug = 1;

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    int yylex_destroy ();
    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno, s);
    }

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    /* Used to generate code */
    /* As printf; the usage: CODEGEN("%d - %s\n", 100, "Hello world"); */
    /* We do not enforce the use of this macro */
    #define CODEGEN(...) \
        do { \
            for (int i = 0; i < g_indent_cnt; i++) { \
                fprintf(fout, "\t"); \
            } \
            fprintf(fout, __VA_ARGS__); \
        } while (0)

    /* Symbol table function - you can add new functions if needed. */
    /* parameters and return type can be changed */
    #define MAX_BUFFER_SIZE 1024
    #define MAX_SYMBOLS 1024
    #define MAX_SCOPE 128

    typedef struct Symbol {
        char name[64];
        int mut;
        char type[16];
        int addr;
        int lineno;
        char func_sig[32];
    } Symbol;

    static Symbol symbol_table[MAX_SCOPE][MAX_SYMBOLS];
    static int symbol_count[MAX_SCOPE] = {0};
    static int block_id[MAX_SCOPE] = {0};

    static int scope_level = -1;
    static int addr_counter = -1;
    static char current_type[16];

    static void create_symbol();
    static void insert_symbol(const char *name, const char *type, const char *func_sig, int mut, int initialize);
    static int lookup_symbol(const char *name);
    static char* lookup_type(const char *name);
    static void dump_symbol();

    /* Global variables */
    bool HAS_ERROR = false;
    bool g_has_error = false;
    FILE *fout = NULL;
    int g_indent_cnt = 0;

    int label_num = 0;
    int while_num = 0;
%}

%error-verbose

/* Use variable or self-defined structure to represent
 * nonterminal and token type
 *  - you can add new fields if needed.
 */
%union {
    int i_val;
    float f_val;
    char *s_val;
    /* ... */
}

/* Token without return */
%token LET MUT NEWLINE
%token INT FLOAT BOOL STR
%token TRUE FALSE
%token GEQ LEQ EQL NEQ LOR LAND
%token ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%token IF ELSE FOR WHILE LOOP
%token PRINT PRINTLN
%token FUNC RETURN BREAK
%token ARROW AS IN DOTDOT RSHIFT LSHIFT

/* Token with return, which need to sepcify type */
%token <i_val> INT_LIT
%token <f_val> FLOAT_LIT
%token <s_val> STRING_LIT
%token <s_val> ID

/* Nonterminal with return, which need to sepcify type */
%type <s_val> Type
%type <s_val> Expression
%type <s_val> Number
%type <s_val> STRING
%type <i_val> MutOpt


%right '=' ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%left LOR
%left LAND
%left '|'
%left '&'
%left EQL NEQ
%left GEQ LEQ '>' '<'
%left LSHIFT RSHIFT
%left '+' '-'
%left '*' '/' '%'
%right UMINUS
%right '!' '~'
%right AS

/* Yacc will start at this nonterminal */
%start Program

/* Grammar section */
%%

Program
    : { create_symbol(); } GlobalStatementList { dump_symbol(); }
;

GlobalStatementList 
    : GlobalStatementList GlobalStatement
    | GlobalStatement
;

GlobalStatement
    : FunctionDeclStmt
    | NEWLINE
;

FunctionDeclStmt
    : FUNC ID { printf("func: %s\n", $2); insert_symbol($2, "func", "(V)V", -1, 1); free($2); } '(' FunctionParamListOpt ')' ReturnTypeOpt Block
;
FunctionParamListOpt
    : /* empty */
    | FunctionParamList
    ;

FunctionParamList
    : FunctionParam
    | FunctionParamList ',' FunctionParam
    ;

FunctionParam
    : ID ':' Type
    ;

ReturnTypeOpt
    : /* empty */
    | ARROW Type
    ;


Block
    : '{' { create_symbol(); } StatementListOpt '}' { dump_symbol(); }
    ;

StatementListOpt
    : /* empty */
    | StatementList
    ;

StatementList
    : Statement
    | StatementList Statement
    ;

Statement
    : Block
    | IF Expression {
        CODEGEN("\tifeq Label_%d\n", label_num);
    } Block {
        CODEGEN("\tgoto End_%d\n", label_num); 
        CODEGEN("\tLabel_%d:\n", label_num);
    } ElseOpt {
        CODEGEN("\tEnd_%d:\n", label_num);
        label_num ++;
    }
    | WHILE {CODEGEN("\tWhite_%d:\n",while_num);} Expression {CODEGEN("\tifeq White_End_%d\n", while_num);} Block {
        CODEGEN("\tgoto White_%d\n", while_num);
        CODEGEN("\tWhite_End_%d:\n", while_num);
        while_num ++;
    }       
    | PRINTLN {CODEGEN("\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n");} '(' Expression ')' ';' {
        
        if($4[0] == 'i')        CODEGEN("\tinvokevirtual java/io/PrintStream/println(I)V\n");
        else if($4[0] == 's')   CODEGEN("\tinvokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n");
        else if($4[0] == 'f')   CODEGEN("\tinvokevirtual java/io/PrintStream/println(F)V\n");
        else if($4[0] == 'b')   CODEGEN("\tinvokevirtual java/io/PrintStream/println(Z)V\n");
    }
    | PRINT   {CODEGEN("\tgetstatic java/lang/System/out Ljava/io/PrintStream;\n");} '(' Expression ')' ';' {
        
        if($4[0] == 'i')        CODEGEN("\tinvokevirtual java/io/PrintStream/print(I)V\n");
        else if($4[0] == 's')   CODEGEN("\tinvokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n");
        else if($4[0] == 'f')   CODEGEN("\tinvokevirtual java/io/PrintStream/print(F)V\n");
        else if($4[0] == 'b')   CODEGEN("\tinvokevirtual java/io/PrintStream/print(Z)V\n");
    }
    | LetDeclStmt
    | ID '=' Expression ';'           {
        int addr = lookup_symbol($1);
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tistore %d\n", addr);
        else if(strcmp(type, "str") == 0)   CODEGEN("\tastore %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfstore %d\n", addr);
        else if(strcmp(type, "bool") == 0)   CODEGEN("\tistore %d\n", addr);
    }
    | ID ADD_ASSIGN {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiload %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfload %d\n", addr);
    } Expression ';' {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiadd\n\tistore %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfadd\n\tfstore %d\n", addr);
    }
    | ID SUB_ASSIGN {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiload %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfload %d\n", addr);
    } Expression ';' {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tisub\n\tistore %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfsub\n\tfstore %d\n", addr);
    }
    | ID MUL_ASSIGN {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiload %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfload %d\n", addr);
    } Expression ';' {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\timul\n\tistore %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfmul\n\tfstore %d\n", addr);
    }
    | ID DIV_ASSIGN {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiload %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfload %d\n", addr);
    } Expression ';' {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tidiv\n\tistore %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfdiv\n\tfstore %d\n", addr);
    }
    | ID REM_ASSIGN {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiload %d\n", addr);
    } Expression ';' {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        if(strcmp(type, "i32") == 0)        CODEGEN("\tirem\n\tistore %d\n", addr);
    }


LetDeclStmt
    : LET MutOpt ID ':' Type '=' Expression ';' { 
        insert_symbol($3, $5, "-", $2, 1); 
    }
    | LET MutOpt ID ':' Type ';' {
        insert_symbol($3, $5, "-", $2, 0);
    }
    | LET MutOpt ID '=' Expression ';' {
        insert_symbol($3, $5, "-", $2, 1); 
    }

ElseOpt
    : ELSE Block
    | 
;

MutOpt
    : MUT               { $$ = 1; }
    | /* empty */       { $$ = 0; }
;

Expression
    : Number {$$ = $1;}
    | ID    {
        int addr = lookup_symbol($1); 
        char *type = lookup_type($1);
        $$ = type;
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiload %d\n", addr);
        else if(strcmp(type, "str") == 0)   CODEGEN("\taload %d\n", addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfload %d\n", addr);
        else if(strcmp(type, "bool") == 0)   CODEGEN("\tiload %d\n", addr);
    }
    | Expression '+' Expression {
        $$ = $1;
        char *type = $1;
        if(strcmp(type, "i32") == 0)        CODEGEN("\tiadd\n");
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfadd\n");
    }
    | Expression '-' Expression {
        $$ = $1;
        char *type = $1;
        if(strcmp(type, "i32") == 0)        CODEGEN("\tisub\n");
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfsub\n");
    }
    | Expression '*' Expression {
        $$ = $1;
        char *type = $1;
        if(strcmp(type, "i32") == 0)        CODEGEN("\timul\n");
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfmul\n");
    }
    | Expression '/' Expression {
        $$ = $1;
        char *type = $1;
        if(strcmp(type, "i32") == 0)        CODEGEN("\tidiv\n");
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfdiv\n");
    }
    | Expression '%' Expression {
        $$ = $1;
        CODEGEN("\tirem\n");
    }
    | '-' Expression        %prec UMINUS    { 
        if (strcmp($2, "i32") == 0)      { CODEGEN("\tineg\n"); } 
        else if (strcmp($2, "f32") == 0) { CODEGEN("\tfneg\n"); }
        printf("NEG\n");
    }
    | '(' Expression ')' {$$ = $2;}
    | Expression '>' Expression {
        char *type = $1; 
        $$ = "bool"; 
        printf("GTR\n");
        if(strcmp(type, "i32") == 0){
            CODEGEN("\tif_icmpgt Label_%d\n", label_num);
            CODEGEN("\t\tldc 0\n");
            CODEGEN("\t\tgoto End_%d\n", label_num);
            CODEGEN("\tLabel_%d:\n", label_num);
            CODEGEN("\t\tldc 1\n");
            CODEGEN("\tEnd_%d:\n", label_num);
            label_num ++;
        }
        else{
            CODEGEN("\tfcmpg\n");
        }
    }
    | '!' Expression   { 
        $$ = "bool";
        printf("NOT\n"); 
        CODEGEN("\tifeq Label_%d\n", label_num);
        CODEGEN("\t\tldc 0\n");
        CODEGEN("\t\tgoto End_%d\n", label_num);
        CODEGEN("\tLabel_%d:\n", label_num);
        CODEGEN("\t\tldc 1\n");
        CODEGEN("\tEnd_%d:\n", label_num);
        label_num ++;
    }
    | Expression LOR Expression  {$$ = "bool"; printf("LOR\n"); CODEGEN("\tior\n");}
    | Expression LAND Expression {$$ = "bool"; printf("LAND\n"); CODEGEN("\tiand\n");}
    | Expression AS Type {
        if(strcmp($1, "i32") == 0 && strcmp($3, "f32") == 0){
            CODEGEN("\ti2f\n");
            $$ = "f32";
        }
        else {
            CODEGEN("\tf2i\n");
            $$ = "i32";
        }

    }
    | Expression EQL Expression {
        CODEGEN("\tif_icmpeq Label_%d\n", label_num);
        CODEGEN("\t\tldc 0\n");
        CODEGEN("\t\tgoto End_%d\n", label_num);
        CODEGEN("\tLabel_%d:\n", label_num);
        CODEGEN("\t\tldc 1\n");
        CODEGEN("\tEnd_%d:\n", label_num);
        label_num ++;
        $$ = "bool";
    }
    | Expression NEQ Expression {
        CODEGEN("\tif_icmpne Label_%d\n", label_num);
        CODEGEN("\t\tldc 0\n");
        CODEGEN("\t\tgoto End_%d\n", label_num);
        CODEGEN("\tLabel_%d:\n", label_num);
        CODEGEN("\t\tldc 1\n");
        CODEGEN("\tEnd_%d:\n", label_num);
        label_num ++;
        $$ = "bool";
    }
    | Expression '<'Expression {
        CODEGEN("\tif_icmplt Label_%d\n", label_num);
        CODEGEN("\t\tldc 0\n");
        CODEGEN("\t\tgoto End_%d\n", label_num);
        CODEGEN("\tLabel_%d:\n", label_num);
        CODEGEN("\t\tldc 1\n");
        CODEGEN("\tEnd_%d:\n", label_num);
        label_num ++;
        $$ = "bool";
    } 
;

Number
    : '"' STRING '"' { $$ = "str"; printf("STRING_LIT \"%s\"\n", $2); CODEGEN("\tldc \"%s\"\n", $2); }
    | INT_LIT        { $$ = "i32"; printf("INT_LIT %d\n", $1);        CODEGEN("\tldc %d\n", $1); }
    | FLOAT_LIT      { $$ = "f32"; printf("FLOAT_LIT %.6f\n", $1);    CODEGEN("\tldc %.6f\n", $1);}
    | BoolNum        { $$ = "bool"; }
    ;

STRING
    : STRING_LIT {$$ = $1; }
    |            {$$ = ""; }
;

BoolNum
    : TRUE  {printf("bool TRUE\n");  CODEGEN("\tldc 1\n");}
    | FALSE {printf("bool FALSE\n"); CODEGEN("\tldc 0\n");}
;

Type
    : INT                           { strcpy(current_type, "i32");  $$ = "i32"; }
    | FLOAT                         { strcpy(current_type, "f32");  $$ = "f32"; }
    | BOOL                          { strcpy(current_type, "bool"); $$ = "bool"; }
    | '&' STR                       { strcpy(current_type, "str");  $$ = "str"; }
    | '[' Type ';' INT_LIT ']'      { printf("INT_LIT %d\n", $4); strcpy(current_type, "array"); $$ = "array"; }
    ;

%%

/* C code section */
int main(int argc, char *argv[])
{
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
    } else {
        yyin = stdin;
    }
    if (!yyin) {
        printf("file `%s` doesn't exists or cannot be opened\n", argv[1]);
        exit(1);
    }

    /* Codegen output init */
    char *bytecode_filename = "hw3.j";
    fout = fopen(bytecode_filename, "w");
    CODEGEN(".source hw3.j\n");
    CODEGEN(".class public Main\n");
    CODEGEN(".super java/lang/Object\n");
    CODEGEN(".method public static main([Ljava/lang/String;)V\n");
    CODEGEN(".limit stack 100\n");
    CODEGEN(".limit locals 100\n");

    /* Symbol table init */
    // Add your code

    yylineno = 0;
    yyparse();

    /* Symbol table dump */
    // Add your code

	printf("Total lines: %d\n", yylineno);

    CODEGEN("\treturn\n.end method\n");

    fclose(fout);
    fclose(yyin);

    if (g_has_error) {
        remove(bytecode_filename);
    }
    yylex_destroy();
    return 0;
}


static void create_symbol() {
    ++scope_level;
    block_id[scope_level]++;
    printf("> Create symbol table (scope level %d)\n", scope_level);
    // printf("> Create symbol table (scope level %d)\n", 0);
    symbol_count[scope_level] = 0;
}

static void insert_symbol(const char *name, const char *type, const char *func_sig, int mut, int initialize) {
    int index = symbol_count[scope_level]++;
    Symbol *sym = &symbol_table[scope_level][index];

    strncpy(sym->name, name, sizeof(sym->name));
    sym->mut = mut;
    strncpy(sym->type, type, sizeof(sym->type));
    sym->addr = addr_counter++;
    sym->lineno = yylineno+1;
    strncpy(sym->func_sig, func_sig, sizeof(sym->func_sig));

    if(initialize == 1){
        if(strcmp(type, "i32") == 0)        CODEGEN("\tistore %d\n", sym->addr);
        else if(strcmp(type, "str") == 0)   CODEGEN("\tastore %d\n", sym->addr);
        else if(strcmp(type, "f32") == 0)   CODEGEN("\tfstore %d\n", sym->addr);
        else if(strcmp(type, "bool") == 0)   CODEGEN("\tistore %d\n", sym->addr);
    }

    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, sym->addr, scope_level);
    // printf("> Insert `%s` (addr: %d) to scope level %d\n", name, addr_counter[scope_level]++, scope_level);
    // printf("> Insert `%s` (addr: %d) to scope level %d\n", "XXX", 0, 0);
}

static int lookup_symbol(const char *name) {
    for(int i=scope_level ; i>=0 ; --i){
        for(int j=0 ; j<symbol_count[i] ; ++j){
            Symbol *sym = &symbol_table[i][j];
            if(strcmp(sym->name, name) == 0){
                return sym->addr;
            }
        }
    }
    return -1;
}

static char* lookup_type(const char *name) {
    for(int i=scope_level ; i>=0; --i){
        for(int j=0 ; j<symbol_count[i] ; ++j){
            Symbol *sym = &symbol_table[i][j];
            if(strcmp(sym->name, name) == 0){
                return sym->type;
            }
        }
    }
    return current_type;
}

static void dump_symbol() {
    printf("\n> Dump symbol table (scope level: %d)\n", scope_level);
    // printf("\n> Dump symbol table (scope level: %d)\n", 0);
    printf("%-10s%-10s%-10s%-10s%-10s%-10s%-10s\n",
        "Index", "Name", "Mut","Type", "Addr", "Lineno", "Func_sig");

    for (int i = 0; i < symbol_count[scope_level]; ++i) {
        Symbol *sym = &symbol_table[scope_level][i];
        printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
            i, sym->name, sym->mut, sym->type, sym->addr, sym->lineno, sym->func_sig);
    }
    /* printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
            0, "name", 0, "type", 0, 0, "func_sig"); */
    symbol_count[scope_level] = 0;
    --scope_level;
}

