
### 📘 **Updated Data Model Summary**

#### **Table: `course_main`**
- Contains all records with a `service_level`:
  - `'F/C'` = **Course/Organization**
  - `'J'` = **Subject**
  - `'P'` = **Program**
  - `'S'` = **System**   - pk1 = 1
  - `'O'` = **Learning Object Repositories**
  

#### **Table: `course_heirarchy`**
- Defines hierarchical relationships between records in `course_main`.
- Fields:
  - `container_crsmain_pk1`: parent record
  - `contained_crsmain_pk1`: child record
  - `distance`: level of containment
    - `1` = direct containment
    - `2` = indirect containment

---

### 📊 **Hierarchy Diagram (Text-Based)**

```
Program (P)
│
├── Subject (J) [distance = 1]
│   └── Course/Org (F/C) [distance = 1]
│
└── Course/Org (F/C) [distance = 2] ← via Subject
```