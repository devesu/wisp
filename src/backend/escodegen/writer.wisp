(ns wisp.backend.escodegen.writer
  (:require [wisp.reader :refer [read-from-string]]
            [wisp.ast :refer [meta with-meta symbol? symbol keyword? keyword
                              namespace unquote? unquote-splicing? quote?
                              syntax-quote? name gensym pr-str]]
            [wisp.sequence :refer [empty? count list? list first second third
                                   rest cons conj reverse reduce vec last map
                                   filter take concat partition interleave]]
            [wisp.runtime :refer [odd? dictionary? dictionary merge keys vals
                                  contains-vector? map-dictionary string?
                                  number? vector? boolean? subs re-find true?
                                  false? nil? re-pattern? inc dec str char
                                  int = ==]]
            [wisp.string :refer [split join upper-case replace]]
            [escodegen :refer [generate]]))


(defn translate-identifier
  "Translates references from clojure convention to JS:

  **macros**      __macros__
  list->vector    listToVector
  set!            set
  foo_bar         foo_bar
  number?         isNumber
  create-server   createServer"
  [form]
  (def id (name form))
  (set! id (cond (identical? id  "*") "multiply"
                 (identical? id "/") "divide"
                 (identical? id "+") "sum"
                 (identical? id "-") "subtract"
                 (identical? id "=") "equal?"
                 (identical? id "==") "strict-equal?"
                 (identical? id "<=") "not-greater-than"
                 (identical? id ">=") "not-less-than"
                 (identical? id ">") "greater-than"
                 (identical? id "<") "less-than"
                 :else id))

  ;; **macros** ->  __macros__
  (set! id (join "_" (split id "*")))
  ;; list->vector ->  listToVector
  (set! id (join "-to-" (split id "->")))
  ;; set! ->  set
  (set! id (join (split id "!")))
  (set! id (join "$" (split id "%")))
  ;; foo= -> fooEqual
  ;(set! id (join "-equal-" (split id "="))
  ;; foo+bar -> fooPlusBar
  (set! id (join "-plus-" (split id "+")))
  (set! id (join "-and-" (split id "&")))
  ;; number? -> isNumber
  (set! id (if (identical? (last id) "?")
             (str "is-" (subs id 0 (dec (count id))))
             id))
  ;; create-server -> createServer
  (set! id (reduce
            (fn [result key]
              (str result
                   (if (and (not (empty? result))
                            (not (empty? key)))
                     (str (upper-case (get key 0)) (subs key 1))
                     key)))
            ""
            (split id "-")))
  id)


;; Operators that compile to binary expressions

(defn make-binary-expression
  [operator left right]
  {:type :BinaryExpression
   :operator operator
   :left left
   :right right})


(defmacro def-binary-operator
  [id operator default-operand make-operand]
  `(set-operator! (name ~id)
                  (fn make-expression
                    ([] (write ~default-operand))
                    ([operand] (write (~make-operand operand)))
                    ([left right] (make-binary-expression ~operator
                                                          (write left)
                                                          (write right)))
                    ([left & more] (make-binary-expression ~operator
                                                          (write left)
                                                          (apply make-expression right))))))

(defn verify-one
  [operator]
  (error (str operator "form requires at least one operand")))

(defn verify-two
  [operator]
  (error (str operator "form requires at least two operands")))

;; Arithmetic operators

;(def-binary-operator :+ :+ 0 identity)
;(def-binary-operator :- :- 'NaN identity)
;(def-binary-operator :* :* 1 identity)
;(def-binary-operator (keyword "/") (keyword "/") verify-two verify-two)
;(def-binary-operator :mod (keyword "%") verify-two verify-two)

;; Comparison operators

;(def-binary-operator :not= :!= verify-one false)
;(def-binary-operator :== :=== verify-one true)
;(def-binary-operator :identical? '=== verify-two verify-two)
;(def-binary-operator :> :> verify-one true)
;(def-binary-operator :>= :>= verify-one true)
;(def-binary-operator :< :< verify-one true)
;(def-binary-operator :<= :<= verify-one true)

;; Bitwise Operators

;(def-binary-operator :bit-and :& verify-two verify-two)
;(def-binary-operator :bit-or :| verify-two verify-two)
;(def-binary-operator :bit-xor (keyword "^") verify-two verify-two)
;(def-binary-operator :bit-not (keyword "~") verify-two verify-two)
;(def-binary-operator :bit-shift-left :<< verify-two verify-two)
;(def-binary-operator :bit-shift-right :>> verify-two verify-two)
;(def-binary-operator :bit-shift-right-zero-fil :>>> verify-two verify-two)


;; Logical operators

(defn make-logical-expression
  [operator left right]
  {:type :LogicalExpression
   :operator operator
   :left left
   :right right})

(defmacro def-logical-expression
  [id operator default-operand make-operand]
  `(set-operator! (name ~id)
                  (fn make-expression
                    ([] (write ~default-operand))
                    ([operand] (write (~make-operand operand)))
                    ([left right] (make-logical-expression ~operator
                                                          (write left)
                                                          (write right)))
                    ([left & more] (make-logical-expression ~operator
                                                          (write left)
                                                          (apply make-expression right))))))

;(def-logical-expression :and :&& 'true identity)
;(def-logical-expression :and :|| 'nil identity)


(defn write-method-call
  [form]
  {:type :CallExpression
   :callee {:type :MemberExpression
            :computed false
            :object (write (first form))
            :property (write (second form))}
   :arguments (map write (vec (rest (rest params))))})

(defn write-instance?
  [form]
  {:type :BinaryExpression
   :operator :instanceof
   :left (write (second form))
   :right (write (first form))})

(defn write-not
  [form]
  {:type :UnaryExpression
   :operator :!
   :argument (write (second form))})





(defn write-location
  [form]
  (let [data (meta form)
        start (:start form)
        end (:end form)]
    (if (not (nil? start))
      {:start {:line (inc (:line start))
               :column (:column start)}
       :end {:line (inc (:line end))
             :column (inc (:column end))}})))

(def *writers* {})
(defn install-writer!
  [op writer]
  (set! (get *writers* op) writer))

(defn write-op
  [op form]
  (let [writer (get *writers* op)]
    (assert writer (str "Unsupported operation: " op))
    (writer form)))

(defn write-nil
  [form]
  {:type :UnaryExpression
   :operator :void
   :argument {:type :Literal
              :value 0}
   :prefix true
   :loc (write-location form)})
(install-writer! :nil write-nil)

(defn write-literal
  [form]
  {:type :Literal
   :value (:form form)
   :loc (write-location form)})
(install-writer! :number write-literal)
(install-writer! :string write-literal)
(install-writer! :boolean write-literal)
(install-writer! :re-pattern write-literal)

(defn write-constant
  [form]
  (let [type (:type form)]
    (cond (= type :list)
          (write-invoke (conj form {:op :invoke
                                    :callee {:op :var
                                             :form 'list}
                                    :params []}))
          :else (write-op type form))))
(install-writer! :constant write-constant)

(defn write-keyword
  [form]
  {:type :Literal
   :value (name (:form form))
   :loc (write-location form)})
(install-writer! :keyword write-keyword)

(defn write-var
  [form]
  {:type :Identifier
   :name (translate-identifier (:form form))
   :loc (write-location form)})
(install-writer! :var write-var)

(defn write-invoke
  [form]
  {:type :CallExpression
   :callee (write (:callee form))
   :arguments (map write (:params form))
   :loc (write-location form)})
(install-writer! :invoke write-invoke)

(defn write-vector
  [form]
  {:type :ArrayExpression
   :elements (map write (:items form))
   :loc (write-location form)})
(install-writer! :vector write-vector)

(defn write-dictionary
  [form]
  (let [properties (partition 2 (interleave (:keys form)
                                            (:values form)))]
    {:type :ObjectExpression
     :properties (map (fn [pair]
                        {:kind :init
                         :type :Property
                         :key (write (first pair))
                         :value (write (second pair))})
                      properties)
     :loc (write-location form)}))
(install-writer! :dictionary write-dictionary)

(defn write-def
  [form]
  {:type :VariableDeclaration
   :kind :var
   :declarations [{:type :VariableDeclarator
                   :id (write-var (:var form))
                   :init (if (nil? (:init form))
                           (write-nil {})
                           (write (:init form)))}]
   :loc (write-location form)})
(install-writer! :def write-def)

(defn write-throw
  [form]
  (->expression {:type :ThrowStatement
                 :argument (write (:throw form))
                 :loc (write-location form)}))
(install-writer! :throw write-throw)

(defn write-new
  [form]
  {:type :NewExpression
   :callee (write (:constructor form))
   :arguments (map write (:params form))
   :loc (write-location form)})
(install-writer! :new write-new)

(defn write-set!
  [form]
  {:type :AssignmentExpression
   :operator :=
   :left (write (:target form))
   :right (write (:value form))
   :loc (write-location form)})
(install-writer! :set! write-set!)

(defn write-aget
  [form]
  {:type :MemberExpression
   :computed (:computed form)
   :object (write (:target form))
   :property (write (:property form))
   :loc (write-location form)})
(install-writer! :member-expression write-aget)

(defn write-statement
  [form]
  (let [op (:op form)]
    (if (or (= op :def)
            (= op :throw)
            (= op :try))
      (write form)
      {:type :ExpressionStatement
       :expression (write form)
       :loc (write-location form)})))

(defn write-body
  [form]
  (let [statements (or (:statements form) [])
        result (:result form)]
    (conj (map write-statement statements)
          (if result
            {:type :ReturnStatement
             :argument (write (:result form))}))))

(defn ->block
  [body]
  {:type :BlockStatement
   :body (if (vector? body)
           body
           [body])})

(defn ->expression
  [body]
  {:type :CallExpression
   :arguments []
   :callee {:type :SequenceExpression
            :expressions [{:type :FunctionExpression
                           :id nil
                           :params []
                           :defaults []
                           :expression false
                           :generator false
                           :rest nil
                           :body (->block body)}]}})

(defn write-do
  [form]
  (->expression (write-body form)))
(install-writer! :do write-do)

(defn write-if
  [form]
  {:type :ConditionalExpression
   :test (write (:test form))
   :consequent (write (:consequent form))
   :alternate (write (:alternate form))
   :loc (write-location form)})
(install-writer! :if write-if)

(defn write-try
  [form]
  (->expression {:type :TryStatement
                 :guardedHandlers []
                 :block (->block (write-body (:body form)))
                 :handlers (if (:handler form)
                             [{:type :CatchClause
                               :param (write (:name (:handler form)))
                               :body (->block (write-body (:handler form)))}]
                             [])
                 :finalizer (if (:finalizer form)
                              (->block (write-body (:finalizer form))))
                 :loc (write-location form)}))
(install-writer! :try write-try)

(defn write
  [form]
  (write-op (:op form) form))

(defn compile
  [form options]
  (generate (write form) options))