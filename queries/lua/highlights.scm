;; extends

((identifier) @namespace.builtin
							(#any-of? @namespace.builtin "Markup"))

; ((variable_declarator)
; 	name: (identifier) @require_var
; 	value: (call_expression
; 		function: (identifier) @require_fn (#eq? @require_fn "require")
; 		arguments: (arguments
; 			(string
; 				(string_fragment) @plugin_name (#eq? @plugin_name "markup")
; 			)
; 		)
; 	)
; )

; (assignment_statement
; 	(variable_list
; 		name: (identifier) @variable.builtin)
; 	(expression_list
; 		value: (function_call
; 						 name: (identifier) (#any-of? "require")
; 						 arguments: (arguments
; 													(string content: (string_content) (#eq? "markup"))))))

; (assignment_statement
;   (variable_list
;     (identifier) @variable.builtin)
;   (expression_list
;     (function_call
;       name: (identifier) @func.name (#eq? @func.name "require")
;       arguments: (arguments
;         (string
;           (string_content) @str.content (#eq? @str.content "markup"))))))

; (assignment_statement
;   (expression_list
;     (function_call
;       name: (identifier) @require.builtin (#eq? @require.builtin "require")
;       arguments: (arguments
;         (string
;           (string_content) (#eq? @str.content "markup")))))
	
; (assignment_statement
;   (variable_list
;     (identifier) @markup.import)
;   (expression_list
;     (function_call
;       name: (identifier) @func.name (#eq? @func.name "require")
;       arguments: (arguments
;         (string (string_content) (#eq? "markup"))))))

; (assignment_statement
;   (variable_list
;     (identifier) @variable.builtin)
;   (expression_list
;     (function_call
;       name: (identifier) @func (#eq? @func "require")
;       arguments: (arguments
;         (string
;           (string_content) (#eq? "markup"))))))
