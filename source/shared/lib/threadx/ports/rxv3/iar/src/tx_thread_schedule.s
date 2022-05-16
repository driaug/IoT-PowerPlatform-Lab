;/**************************************************************************/
;/*                                                                        */
;/*       Copyright (c) Microsoft Corporation. All rights reserved.        */
;/*                                                                        */
;/*       This software is licensed under the Microsoft Software License   */
;/*       Terms for Microsoft Azure RTOS. Full text of the license can be  */
;/*       found in the LICENSE file at https://aka.ms/AzureRTOS_EULA       */
;/*       and in the root directory of this software.                      */
;/*                                                                        */
;/**************************************************************************/
;
;
;/**************************************************************************/
;/**************************************************************************/
;/**                                                                       */ 
;/** ThreadX Component                                                     */ 
;/**                                                                       */
;/**   Thread                                                              */
;/**                                                                       */
;/**************************************************************************/
;/**************************************************************************/
;
;
;#define TX_SOURCE_CODE
;
;
;/* Include necessary system files.  */
;
;#include "tx_api.h"
;#include "tx_thread.h"
;#include "tx_timer.h"
;
;
    extern __tx_thread_execute_ptr
    extern __tx_thread_current_ptr
    extern __tx_timer_time_slice

    section .text:CODE:ROOT

;/**************************************************************************/ 
;/*                                                                        */ 
;/*  FUNCTION                                               RELEASE        */ 
;/*                                                                        */ 
;/*    _tx_thread_schedule                                  RXv3/IAR       */
;/*                                                           6.1.9        */
;/*  AUTHOR                                                                */ 
;/*                                                                        */ 
;/*    William E. Lamie, Microsoft Corporation                             */
;/*                                                                        */ 
;/*  DESCRIPTION                                                           */ 
;/*                                                                        */ 
;/*    This function waits for a thread control block pointer to appear in */ 
;/*    the _tx_thread_execute_ptr variable.  Once a thread pointer appears */ 
;/*    in the variable, the corresponding thread is resumed.               */ 
;/*                                                                        */ 
;/*  INPUT                                                                 */ 
;/*                                                                        */ 
;/*    None                                                                */ 
;/*                                                                        */ 
;/*  OUTPUT                                                                */ 
;/*                                                                        */ 
;/*    None                                                                */
;/*                                                                        */ 
;/*  CALLS                                                                 */ 
;/*                                                                        */ 
;/*    None                                                                */
;/*                                                                        */ 
;/*  CALLED BY                                                             */ 
;/*                                                                        */ 
;/*    _tx_initialize_kernel_enter          ThreadX entry function         */ 
;/*    _tx_thread_system_return             Return to system from thread   */ 
;/*    _tx_thread_context_restore           Restore thread's context       */ 
;/*                                                                        */ 
;/*  RELEASE HISTORY                                                       */ 
;/*                                                                        */ 
;/*    DATE              NAME                      DESCRIPTION             */ 
;/*                                                                        */ 
;/*  06-02-2021     William E. Lamie         Initial Version 6.1.7         */
;/*  10-15-2021     William E. Lamie         Modified comment(s), and      */ 
;/*                                            added FPU support,          */ 
;/*                                            resulting in version 6.1.9  */ 
;/*                                                                        */ 
;/**************************************************************************/ 
;VOID   _tx_thread_schedule(VOID)
;{
    public __tx_thread_schedule

__tx_thread_schedule:
;
;    /* Enable interrupts.  */
;
    SETPSW I
;
;    /* Wait for a thread to execute.  */
;    do
;    {
    MOV.L    #__tx_thread_execute_ptr, R1       ; Address of thread to executer ptr
__tx_thread_schedule_loop:
    MOV.L    [R1],R2                            ; Pickup next thread to execute
    CMP      #0,R2                              ; Is it NULL?
    BEQ      __tx_thread_schedule_loop          ; Yes, idle system, keep checking
;
;    }
;    while(_tx_thread_execute_ptr == TX_NULL);
;    
;    /* Yes! We have a thread to execute.  Lockout interrupts and
;       transfer control to it.  */
;
    CLRPSW I                                    ; Disable interrupts
;
;    /* Setup the current thread pointer.  */
;    _tx_thread_current_ptr =  _tx_thread_execute_ptr;
;
    MOV.L    #__tx_thread_current_ptr, R3
    MOV.L    R2,[R3]                            ; Setup current thread pointer
;
;    /* Increment the run count for this thread.  */
;    _tx_thread_current_ptr -> tx_thread_run_count++;
;
    MOV.L    4[R2],R3                           ; Pickup run count  
    ADD      #1,R3                              ; Increment run counter
    MOV.L    R3,4[R2]                           ; Store it back in control block
;
;    /* Setup time-slice, if present.  */
;    _tx_timer_time_slice =  _tx_thread_current_ptr -> tx_thread_time_slice;
;
    MOV.L    24[R2],R3                          ; Pickup thread time-slice
    MOV.L    #__tx_timer_time_slice,R4          ; Pickup pointer to time-slice
    MOV.L    R3, [R4]                           ; Setup time-slice                        
;
;    /* Switch to the thread's stack.  */
;    SP =  _tx_thread_execute_ptr -> tx_thread_stack_ptr;
    SETPSW U                                    ; User stack mode
    MOV.L   8[R2],R0                            ; Pickup stack pointer

#if (__DPFPU == 1)
    MOV.L   144[R2], R1                         ; Get tx_thread_fpu_enable.
    CMP     #0, R1
    BEQ     __tx_thread_schedule_fpu_skip

    DPOPM.L DPSW-DECNT                          ; Restore FPU register bank if tx_thread_fpu_enable is not 0.
    DPOPM.D DR0-DR15

__tx_thread_schedule_fpu_skip:
#endif

    POPM    R1-R3                               ; Restore accumulators.
    MVTACLO R3, A0
    MVTACHI R2, A0
    MVTACGU R1, A0
    POPM    R1-R3
    MVTACLO R3, A1
    MVTACHI R2, A1
    MVTACGU R1, A1
    
    POPM   R6-R13                               ; Recover interrupt stack frame
    POPC   FPSW 
    POPM   R14-R15
    POPM   R3-R5
    POPM   R1-R2    
    RTE                                         ; Return to point of interrupt, this restores PC and PSW

;
;}

    extern __tx_thread_context_save
    extern __tx_thread_context_restore

; Software triggered interrupt used to perform context switches.
; The priority of this interrupt is set to the lowest priority within
; tx_initialize_low_level() and triggered by ThreadX when calling
; _tx_thread_system_return().
    public ___interrupt_27
___interrupt_27:

    PUSHM R1-R2

    BSR __tx_thread_context_save

    BRA __tx_thread_context_restore


; Enable saving of DFPU registers for the current thread.
; If DPFU op are disabled do nothing.
    public _tx_thread_fpu_enable
_tx_thread_fpu_enable:
#if (__DPFPU == 1)
    PUSHM    R1-R4
    MVFC     PSW, R2                            ; Save PSW to R2
    CLRPSW   I                                  ; Lockout interrupts

    MOV.L    #__tx_thread_current_ptr, R4
    MOV.L    [R4], R1                           ; Fetch current thread pointer

    MOV.L    #1, R3
    MOV.L    R3, 144[R1]                        ; Set tx_thread_fpu_enable to 1.

__tx_thread_fpu_enable_exit:
    MVTC     R2, PSW                            ; Restore interrupt status
    POPM     R1-R4
#endif
    RTS


; Disable saving of DFPU registers for the current thread.
; If DPFU op are disabled do nothing.
    public _tx_thread_fpu_disable
_tx_thread_fpu_disable:
#if (__DPFPU == 1)
    PUSHM    R1-R4
    MVFC     PSW, R2                            ; Save PSW to R2
    CLRPSW   I                                  ; Lockout interrupts

    MOV.L    #__tx_thread_current_ptr, R4
    MOV.L    [R4], R1                           ; Fetch current thread pointer

    MOV.L    #1, R3
    MOV.L    R3, 144[R1]                        ; Set tx_thread_fpu_enable to 1.

__tx_thread_fpu_disable_exit:
    MVTC     R2, PSW                            ; Restore interrupt status
    POPM     R1-R4
#endif
    RTS

    END

