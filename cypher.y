%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "postgres_fe.h"                                                        
                                                                                
#include "psqlscanslash.h"                                                      
#include "common/logging.h"                                                     
#include "fe_utils/conditional.h"  

#include "fe_utils/psqlscan_int.h"    
#include "fe_utils/psqlscan.h"                                         
                                                                                
#include "libpq-fe.h"                                                           
#include "cypherscan.h"                                                         
#include "cypher.tab.h" 

void yyerror(void* scanner, char const *s);

typedef struct yy_buffer_state *YY_BUFFER_STATE;

typedef struct
{
    char* str_val;
    int int_val;
} yyval;

int order_clause_direction = 1; // 1 for ascending, -1 for descending

int match = 0;
char* label1 = "NULL";
char* label2 = "NULL";
char* property = "NULL";
int expression_int = -1;
char* expression_str = "NULL";
char* expression_id = "NULL";
int directed = 0;
char* direction = "NULL";
int where = 0;
int with = 0;
int return_ = 0;
int with_alias = 0;
int order_by = 0;
int skip_value = 0;
int limit_value = 0;
%}

%union
{
    char* str_val;
    int int_val;
}

%token ASC ARROW AS DESC LBRACKET RBRACKET LPAREN RPAREN COLON PIPE COMMA SEMICOLON LBRACE RBRACE MATCH WHERE WITH ORDER BY SKIP LIMIT RETURN
%token <int_val> INTEGER
%token <str_val> IDENTIFIER STRING
%token UNKNOWN

%type <str_val> str_val

%param {void* scanner}

%left PIPE
%left ARROW

%start statement

%%

statement:
    query
;

query:
    match_clause
    where_clause_opt
    with_clause_opt
    return_clause
    ;

match_clause:
    MATCH path_pattern 
        {
            match = 1;
        }
    ;    

path_pattern:
    node_pattern
    | node_pattern ARROW rel_pattern node_pattern
    ;

node_pattern:
    LPAREN node_labels_opt node_properties_opt RPAREN
    ;

node_labels_opt:
    /* empty */ 
        { 
            label1 = "NULL"; 
            label2 = "NULL";
        }
    |
      IDENTIFIER
        {
            label1 = $1;
        }
    | COLON IDENTIFIER 
        {
            label1 = $2;
        }
    | node_labels_opt COLON IDENTIFIER 
        {
            label2 = $3;
        }
    ;

node_properties_opt:
    /* empty */ 
        { 
            property = "NULL"; 
        }
    | LBRACE map_literal RBRACE
    ;

str_val:
    IDENTIFIER 
        {
            $$ = $1;
        }
    | STRING 
        {
            $$ = $1;
        }
    ;

rel_pattern:
    rel_type rel_direction rel_type 
        {
            directed = 1;
        }
    ;

rel_type:
    COLON str_val
    | LBRACKET str_val RBRACKET
    ;

rel_direction:
    ARROW 
        {
            direction = "->";
        }
    | ARROW str_val ARROW
    ;

map_literal:
    /* empty */
    | nonempty_map_literal
    ;

nonempty_map_literal:
    map_entry
    | nonempty_map_literal COMMA map_entry
    ;

map_entry:
    IDENTIFIER COLON expression 
        {
            property = $1;
        }
    ;

expression:
    INTEGER 
        {
            expression_int = $1;
        }
    | STRING 
        {
            expression_str = $1;
        }
    | IDENTIFIER 
        {
            expression_id = $1;
        }
    ;

where_clause_opt:
    /* empty */ 
        {
            where = 0;
        }
    | WHERE expression 
        { 
            where = 1;
        }
    ;

with_clause_opt:
    /* empty */ 
        {
            with = 0;
        }
    | WITH expression_list return_clause 
        {
            with = 1;
        }
        ;

expression_list:
	expression
	| expression_list COMMA expression
	;

return_clause:
	RETURN return_item_list order_clause_opt skip_clause_opt limit_clause_opt 
            {
                return_ = 1;
            }
        ;

return_item_list:
	return_item
	| return_item_list COMMA return_item
	;

return_item:
	expression
	| expression AS IDENTIFIER 
            {
                with_alias = 1;
            }
	;

order_clause_opt:
	/* empty */ 
            {
                order_by = 0;
            }
	| ORDER BY sort_item_list 
            {
                order_by = 1;
            }
	;

sort_item_list:
    sort_item
    | sort_item_list COMMA sort_item
    ;

sort_item:
    expression sort_direction_opt
    ;

sort_direction_opt:
    /* empty */ 
        {
            printf("Sort direction not specified; defaulting to ASC.\n");
            order_clause_direction = 1;
        }
    | ASC 
        {
            printf("Sort direction specified: ASC.\n"); 
            order_clause_direction = 1;
        }
    | DESC 
        {
            printf("Sort direction specified: DESC.\n"); 
            order_clause_direction = -1;
        }
    ;

skip_clause_opt:
    /* empty */
    | SKIP INTEGER 
        {
            skip_value = $2;
        }
    ;

limit_clause_opt:
    /* empty */
    | LIMIT INTEGER
        {
            limit_value = $2;
        }
    ;

%%

void yyerror(void* scanner, char const *s)
{
	printf("Parser error: %s\n", s);
}

char*
psql_scan_cypher_command(PsqlScanState state)
{ 
    PQExpBufferData mybuf;

    /* Must be scanning already */
    Assert(state->scanbufhandle != NULL);

    /* Build a local buffer that we'll return the data of */
    initPQExpBuffer(&mybuf);

    /* Set current output target */
    state->output_buf = &mybuf;

    /* Set input source */
    if (state->buffer_stack != NULL)
            yy_switch_to_buffer(state->buffer_stack->buf, state->scanner);
    else
            yy_switch_to_buffer(state->scanbufhandle, state->scanner);

    /* And lex. */
    yyparse(state->scanner);

    if (match == 1) { 
        state->start_state = 1;
    }

    mybuf.data = state->scanbuf;

    /* There are no possible errors in this lex state... */

    /*
     * In case the caller returns to using the regular SQL lexer, reselect the
     * appropriate initial state.
     */
    psql_scan_reselect_sql_lexer(state);

    return mybuf.data;
}
