! <My_Pollen_ml.f90 - A component of the EMEP MSC-W Chemical transport Model, version rv4_10(3282)>
!*****************************************************************************!
!*
!*  Copyright (C) 2007-2016 met.no
!*
!*  Contact information:
!*  Norwegian Meteorological Institute
!*  Box 43 Blindern
!*  0313 OSLO
!*  NORWAY
!*  email: emep.mscw@met.no
!*  http://www.emep.int
!*
!*    This program is free software: you can redistribute it and/or modify
!*    it under the terms of the GNU General Public License as published by
!*    the Free Software Foundation, either version 3 of the License, or
!*    (at your option) any later version.
!*
!*    This program is distributed in the hope that it will be useful,
!*    but WITHOUT ANY WARRANTY; without even the implied warranty of
!*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!*    GNU General Public License for more details.
!*
!*    You should have received a copy of the GNU General Public License
!*    along with this program.  If not, see <http://www.gnu.org/licenses/>.
!*****************************************************************************!
!-----------------------------------------------------------------------!
! Empty Pollen rountines for "standrd" model compilation
!-----------------------------------------------------------------------!
! Birch pollen emission calculation based on
! M. Sofiev et al. 2006, doi:10.1007/s00484-006-0027-x
!
! Pollen emission based upon meteorology paparameters, and heatsum.
! Pollen particles are assumed of 22 um diameter and 800 kg/m3 density. 
!-----------------------------------------------------------------------!
module Pollen_const_ml
use PhysicalConstants_ml, only: PI
use ModelConstants_ml,    only: USE_POLLEN,DEBUG=>DEBUG_POLLEN
use ChemSpecs,            only: species_adv
use CheckStop_ml,         only: CheckStop
implicit none
public

real, parameter :: &
  D_POLL   = 22e-6,     & ! Pollen grain diameter [m]
  POLL_DENS= 800e3        ! Pollen density [g/m3]

real, parameter :: &
  grain_wt = POLL_DENS*PI*D_POLL**3/6.0, &  ! 1 grain weight [g]
  ug2grains= 1e-6/grain_wt                  ! # grains in 1 ug

real, parameter  :: &
  N_TOT(3)=1.0  ! avoid div0

contains

subroutine pollen_check(igrp)
  integer, intent(out), optional :: igrp
  logical,save :: first_call=.true.
  if(present(igrp))igrp=-1
  if(.not.first_call)return
  first_call=.false.
  call CheckStop(USE_POLLEN.or.DEBUG,&
    "USE_POLLEN/DEBUG_POLLEN on model compiled without pollen modules")
endsubroutine pollen_check
endmodule Pollen_const_ml
!-----------------------------------------------------------------------!
! Empty Pollen rountines for "standrd" model compilation
!-----------------------------------------------------------------------!
! Birch pollen emission calculation based on
! M. Sofiev et al. 2006, doi:10.1007/s00484-006-0027-x
!
! Pollen emission based upon meteorology paparameters, and heatsum.
! Pollen particles are assumed of 22 um diameter and 800 kg/m3 density. 
!-----------------------------------------------------------------------!
module Pollen_ml
use Pollen_const_ml
implicit none
public:: pollen_flux,pollen_dump,pollen_read,pollen_check

real,public,save, allocatable,dimension(:,:,:) :: &
  heatsum,      & ! heatsum, needs to be remembered for forecast
  AreaPOLL,     & ! emission of pollen 
  R               ! pollen released so far

contains

subroutine pollen_flux(i,j,debug_flag) 
  implicit none
  integer, intent(in) :: i,j    ! coordinates of column
  logical, intent(in) :: debug_flag
  call pollen_check()
endsubroutine pollen_flux

subroutine pollen_read()
  call pollen_check()
endsubroutine pollen_read

subroutine pollen_dump()
  call pollen_check()
endsubroutine pollen_dump
endmodule Pollen_ml
