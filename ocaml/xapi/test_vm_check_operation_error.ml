
let with_test_vm f =
  let __context = Mock.make_context_with_new_db "Mock context" in
  let vm_ref = Test_common.make_vm ~__context () in
  f __context vm_ref

(* CA-255128 Xapi_vm_lifecycle.check_operation_error should not throw an
   exception even when all the VM record's nullable fields are null and the VM
   has a VBD with a null VDI. *)
let test_null_vdi () =
  with_test_vm (fun __context vm_ref ->
      (* It is valid for one of the VM's VBDs to have a null VDI:
         A read-only, empty, CD VBD has a null VDI *)
      let () = ignore(Test_common.make_vbd ~__context ~vM:vm_ref ~_type:`CD ~mode:`RO ~empty:true ~vDI:Ref.null ()) in
      List.iter
        (fun op -> ignore(Xapi_vm_lifecycle.check_operation_error ~__context ~ref:vm_ref ~op ~strict:true))
        Xapi_vm_lifecycle.all_vm_operations
    )

(* Operations that check the validity of other VM operations should
   always be allowed *)
let test_operation_checks_allowed () =
  with_test_vm (fun __context vm_ref ->
      [`assert_operation_valid; `update_allowed_operations] |>
      List.iter
        (fun op -> OUnit.assert_equal None (Xapi_vm_lifecycle.check_operation_error ~__context ~ref:vm_ref ~op ~strict:true))
    )

let test_migration_disallowed_when_cbt_enabled () =
  with_test_vm (fun __context vm_ref ->
      let vdi_ref = Test_common.make_vdi ~__context ~cbt_enabled:true () in
      let () = ignore(Test_common.make_vbd ~__context ~vM:vm_ref ~vDI:vdi_ref ()) in
      OUnit.assert_equal
        (Some(Api_errors.vdi_cbt_enabled, [ Ref.string_of vdi_ref ]))
        (Xapi_vm_lifecycle.check_operation_error ~__context ~ref:vm_ref ~op:`migrate_send ~strict:true)
    )

let test_sxm_disallowed_when_rum () =
  with_test_vm (fun __context vm_ref ->
    let master = Test_common.make_host __context () in
    let pool = Test_common.make_pool ~__context ~master () in
    Db.Pool.add_to_other_config ~__context ~self:pool ~key:Xapi_globs.rolling_upgrade_in_progress ~value:"x";
    OUnit.assert_equal
      (Some(Api_errors.not_supported_during_upgrade, [ ]))
      (Xapi_vm_lifecycle.check_operation_error ~__context ~ref:vm_ref ~op:`migrate_send ~strict:false);
    Db.Pool.remove_from_other_config ~__context ~self:pool ~key:Xapi_globs.rolling_upgrade_in_progress;
    OUnit.assert_equal
      None
      (Xapi_vm_lifecycle.check_operation_error ~__context ~ref:vm_ref ~op:`migrate_send ~strict:false)
  )

let test =
  let open OUnit in
  "test_vm_check_operation_error" >:::
  [ "test_null_vdi" >:: test_null_vdi
  ; "test_operation_checks_allowed" >:: test_operation_checks_allowed
  ; "test_migration_disallowed_when_cbt_enabled" >:: test_migration_disallowed_when_cbt_enabled
  ; "test_sxm_disallowed_when_rum" >:: test_sxm_disallowed_when_rum
  ]
